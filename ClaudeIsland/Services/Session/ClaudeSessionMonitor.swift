//
//  ClaudeSessionMonitor.swift
//  ClaudeIsland
//
//  MainActor wrapper around SessionStore for UI binding.
//  Publishes SessionState arrays for SwiftUI observation.
//

import AppKit
import Combine
import Foundation
import Network
import SwiftUI

// MARK: - ClaudeSessionMonitoring Protocol

/// Protocol for session monitoring and UI binding
@MainActor
protocol ClaudeSessionMonitoring: ObservableObject {
    /// All active session instances
    var instances: [SessionState] { get set }
    
    /// Sessions that need user attention
    var pendingInstances: [SessionState] { get set }
    
    /// HTTP server for hook events
    var httpServer: LocalHTTPServer { get }
    
    /// Start monitoring for session events
    func startMonitoring()
    
    /// Stop monitoring for session events
    func stopMonitoring()
    
    /// Approve a permission request for a session
    func approvePermission(sessionId: String)
    
    /// Deny a permission request for a session
    func denyPermission(sessionId: String, reason: String?)
    
    /// Submit an interactive response to a permission request
    func submitInteractiveResponse(sessionId: String, message: String) async -> Bool
    
    /// Archive (remove) a session from the instances list
    func archiveSession(sessionId: String)
    
    /// Request history load for a session
    func loadHistory(sessionId: String, cwd: String)
}

@MainActor
class ClaudeSessionMonitor: ClaudeSessionMonitoring {
    static let shared = ClaudeSessionMonitor()

    @Published var instances: [SessionState] = []
    @Published var pendingInstances: [SessionState] = []

    /// The new HTTP server for hook events (Masko-style)
    let httpServer = LocalHTTPServer()

    private var cancellables = Set<AnyCancellable>()
    private var isMonitoringStarted = false
    private var pendingHTTPPermissions: [String: NWConnection] = [:]
    private let httpToolUseIdCache = LRUCache<String, [String]>(capacity: 1000)
    private let sessionStore: SessionStoring

    init(sessionStore: SessionStoring = SessionStore.shared) {
        self.sessionStore = sessionStore
        sessionStore.sessionsPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] sessions in
                self?.updateFromSessions(sessions)
            }
            .store(in: &cancellables)

        InterruptWatcherManager.shared.delegate = self

        httpServer.onPermissionRequest = { [weak self] event, connection in
            Task { @MainActor in
                self?.registerPendingHTTPPermission(for: event, connection: connection)
            }
        }

        httpServer.onEventReceived = { [weak self] event in
            Task { @MainActor in
                await self?.forwardHTTPHookEvent(event)
            }
        }
    }

    // MARK: - Monitoring Lifecycle

    func startMonitoring() {
        if !isMonitoringStarted {
            isMonitoringStarted = true

            HookSocketServer.shared.start(
                onEvent: { event in
                    Task { [weak self] in
                        guard let self else { return }
                        await sessionStore.process(.hookReceived(event))
                        let session = await sessionStore.session(for: event.sessionId)
                        await MainActor.run {
                            ClaudeHookPopupManager.shared.handleHookEvent(event, session: session)
                        }
                    }

                    if event.sessionPhase == .processing {
                        Task { @MainActor in
                            InterruptWatcherManager.shared.startWatching(
                                sessionId: event.sessionId,
                                cwd: event.cwd
                            )
                        }
                    }

                    if event.status == "ended" {
                        Task { @MainActor in
                            InterruptWatcherManager.shared.stopWatching(sessionId: event.sessionId)
                        }
                    }

                    if event.event == "Stop" {
                        HookSocketServer.shared.cancelPendingPermissions(sessionId: event.sessionId)
                    }

                    if event.event == "PostToolUse", let toolUseId = event.toolUseId {
                        HookSocketServer.shared.cancelPendingPermission(toolUseId: toolUseId)
                    }
                },
                onPermissionFailure: { [weak self] sessionId, toolUseId in
                    Task {
                        await self?.sessionStore.process(
                            .permissionSocketFailed(sessionId: sessionId, toolUseId: toolUseId)
                        )
                    }
                }
            )
        }

        if AppSettings.hookMonitorEnabled && !httpServer.isRunning {
            try? httpServer.start()
        } else if !AppSettings.hookMonitorEnabled && httpServer.isRunning {
            httpServer.stop()
        }
    }

    func stopMonitoring() {
        isMonitoringStarted = false
        HookSocketServer.shared.stop()
        httpServer.stop()
        ClaudeHookPopupManager.shared.hide()
        for (_, connection) in pendingHTTPPermissions {
            connection.cancel()
        }
        pendingHTTPPermissions.removeAll()
        httpToolUseIdCache.removeAll()
    }

    // MARK: - Permission Handling

    func approvePermission(sessionId: String) {
        Task {
            guard let session = await sessionStore.session(for: sessionId),
                  let permission = session.activePermission else {
                return
            }

            await MainActor.run {
                respondToPendingPermission(sessionId: sessionId, toolUseId: permission.toolUseId, approved: true, reason: nil)
            }

            await sessionStore.process(
                .permissionApproved(sessionId: sessionId, toolUseId: permission.toolUseId)
            )
        }
    }

    func denyPermission(sessionId: String, reason: String?) {
        Task {
            guard let session = await sessionStore.session(for: sessionId),
                  let permission = session.activePermission else {
                return
            }

            await MainActor.run {
                respondToPendingPermission(sessionId: sessionId, toolUseId: permission.toolUseId, approved: false, reason: reason)
            }

            await sessionStore.process(
                .permissionDenied(sessionId: sessionId, toolUseId: permission.toolUseId, reason: reason)
            )
        }
    }

    func interruptSession(sessionId: String) async {
        // Send interrupt signal to the CLI process
        await CLISessionManager.shared.interruptSession(threadId: sessionId)
    }

    func submitInteractiveResponse(sessionId: String, message: String) async -> Bool {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let session = await sessionStore.session(for: sessionId),
              let permission = session.activePermission else {
            return false
        }

        let responded = await MainActor.run {
            respondToInteractivePrompt(
                sessionId: sessionId,
                toolUseId: permission.toolUseId,
                message: trimmed
            )
        }

        guard responded else { return false }

        await sessionStore.process(
            .permissionApproved(sessionId: sessionId, toolUseId: permission.toolUseId)
        )
        return true
    }

    /// Archive (remove) a session from the instances list
    func archiveSession(sessionId: String) {
        Task {
            await sessionStore.process(.sessionEnded(sessionId: sessionId))
        }
    }

    // MARK: - State Update

    private func updateFromSessions(_ sessions: [SessionState]) {
        instances = sessions
        pendingInstances = sessions.filter { $0.needsAttention }
    }

    private func forwardHTTPHookEvent(_ event: HTTPHookEvent) async {
        guard let hookEvent = makeHookEvent(from: event) else { return }

        if hookEvent.event == "Stop" || hookEvent.event == "SessionEnd" || hookEvent.status == "ended" {
            dismissPendingHTTPPermission(sessionId: hookEvent.sessionId)
            cleanupHTTPToolUseCache(sessionId: hookEvent.sessionId)
        }

        await sessionStore.process(.hookReceived(hookEvent))
        let session = await sessionStore.session(for: hookEvent.sessionId)
        ClaudeHookPopupManager.shared.handleHookEvent(hookEvent, session: session)
    }

    private func registerPendingHTTPPermission(for event: HTTPHookEvent, connection: NWConnection) {
        guard let sessionId = normalizeCLISessionId(event.sessionId) else { return }
        pendingHTTPPermissions[sessionId] = connection
    }

    private func respondToPendingPermission(sessionId: String, toolUseId: String, approved: Bool, reason: String?) {
        let normalizedSessionId = normalizeCLISessionId(sessionId) ?? sessionId

        if let connection = pendingHTTPPermissions.removeValue(forKey: normalizedSessionId) {
            httpServer.respondToPermission(connection: connection, approved: approved)
        } else if !toolUseId.isEmpty {
            HookSocketServer.shared.respondToPermission(
                toolUseId: toolUseId,
                decision: approved ? "allow" : "deny",
                reason: reason
            )
        } else {
            HookSocketServer.shared.respondToPermissionBySession(
                sessionId: normalizedSessionId,
                decision: approved ? "allow" : "deny",
                reason: reason
            )
        }
    }

    private func dismissPendingHTTPPermission(sessionId: String) {
        guard let connection = pendingHTTPPermissions.removeValue(forKey: sessionId) else { return }
        httpServer.respondToPermission(connection: connection, approved: false)
    }

    private func respondToInteractivePrompt(sessionId: String, toolUseId: String, message: String) -> Bool {
        let normalizedSessionId = normalizeCLISessionId(sessionId) ?? sessionId

        if let connection = pendingHTTPPermissions.removeValue(forKey: normalizedSessionId) {
            httpServer.respondToPermission(connection: connection, approved: true, body: message)
            return true
        }

        if !toolUseId.isEmpty {
            HookSocketServer.shared.respondToPermission(
                toolUseId: toolUseId,
                decision: "ask",
                reason: message
            )
            return true
        }

        HookSocketServer.shared.respondToPermissionBySession(
            sessionId: normalizedSessionId,
            decision: "ask",
            reason: message
        )
        return true
    }

    private func makeHookEvent(from event: HTTPHookEvent) -> HookEvent? {
        guard let rawSessionId = event.sessionId,
              let sessionId = normalizeCLISessionId(rawSessionId),
              let cwd = event.cwd,
              !cwd.isEmpty else {
            return nil
        }

        let eventName = event.hookEventName ?? "Notification"
        let toolName = event.toolName ?? event.permissionRequest?.tool
        let toolInput = parseToolInput(rawToolInput: event.toolInput, permissionInput: event.permissionRequest?.input)

        var toolUseId = event.toolUseId
        if eventName == "PreToolUse", let toolUseId {
            cacheHTTPToolUseId(
                sessionId: sessionId,
                toolName: toolName,
                toolInput: toolInput,
                toolUseId: toolUseId
            )
        } else if eventName == "PermissionRequest", toolUseId == nil {
            toolUseId = popCachedHTTPToolUseId(
                sessionId: sessionId,
                toolName: toolName,
                toolInput: toolInput
            )
        }

        return HookEvent(
            sessionId: sessionId,
            cwd: cwd,
            event: eventName,
            status: status(for: eventName, notificationType: event.notificationType),
            pid: event.shellPid ?? event.terminalPid,
            tty: nil,
            tool: toolName,
            toolInput: toolInput,
            toolUseId: toolUseId,
            notificationType: event.notificationType,
            message: event.content ?? event.permissionRequest?.description
        )
    }

    private func status(for eventName: String, notificationType: String?) -> String {
        switch eventName {
        case "PermissionRequest":
            return "waiting_for_approval"
        case "PreToolUse", "UserPromptSubmit", "SessionStart", "SubagentStart", "SubagentStop", "PostToolUse", "PostToolUseFailure":
            return "processing"
        case "PreCompact":
            return "compacting"
        case "TaskCompleted", "Stop":
            return "waiting_for_input"
        case "SessionEnd":
            return "ended"
        case "Notification":
            return notificationType == "idle_prompt" ? "waiting_for_input" : "idle"
        default:
            return "idle"
        }
    }

    private func parseToolInput(rawToolInput: String?, permissionInput: String?) -> [String: AnyCodable]? {
        if let rawToolInput, let parsed = parseJSONInput(rawToolInput) {
            return parsed
        }

        if let permissionInput, let parsed = parseJSONInput(permissionInput) {
            return parsed
        }

        if let fallback = rawToolInput?.trimmingCharacters(in: .whitespacesAndNewlines),
           !fallback.isEmpty {
            return ["input": AnyCodable(fallback)]
        }

        if let fallback = permissionInput?.trimmingCharacters(in: .whitespacesAndNewlines),
           !fallback.isEmpty {
            return ["input": AnyCodable(fallback)]
        }

        return nil
    }

    private func parseJSONInput(_ rawValue: String) -> [String: AnyCodable]? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let data = trimmed.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) else {
            return nil
        }

        if let dictionary = object as? [String: Any] {
            return dictionary.mapValues { AnyCodable($0) }
        }

        if let array = object as? [Any] {
            return ["input": AnyCodable(array)]
        }

        return ["input": AnyCodable(object)]
    }

    private func cacheHTTPToolUseId(
        sessionId: String,
        toolName: String?,
        toolInput: [String: AnyCodable]?,
        toolUseId: String
    ) {
        let key = cacheKey(sessionId: sessionId, toolName: toolName, toolInput: toolInput)
        var queue = httpToolUseIdCache.get(key) ?? []
        queue.append(toolUseId)
        httpToolUseIdCache.set(key, value: queue)
    }

    private func popCachedHTTPToolUseId(
        sessionId: String,
        toolName: String?,
        toolInput: [String: AnyCodable]?
    ) -> String? {
        let key = cacheKey(sessionId: sessionId, toolName: toolName, toolInput: toolInput)
        guard var queue = httpToolUseIdCache.get(key), !queue.isEmpty else {
            return nil
        }

        let toolUseId = queue.removeFirst()
        if queue.isEmpty {
            httpToolUseIdCache.remove(key)
        } else {
            httpToolUseIdCache.set(key, value: queue)
        }
        return toolUseId
    }

    private func cleanupHTTPToolUseCache(sessionId: String) {
        let prefix = "\(sessionId):"
        let keys = httpToolUseIdCache.allKeys().filter { $0.hasPrefix(prefix) }
        for key in keys {
            httpToolUseIdCache.remove(key)
        }
    }

    private func cacheKey(
        sessionId: String,
        toolName: String?,
        toolInput: [String: AnyCodable]?
    ) -> String {
        let serializedInput: String
        if let toolInput {
            let rawInput = toolInput.mapValues(\.value)
            if let data = try? JSONSerialization.data(withJSONObject: rawInput, options: [.sortedKeys]),
               let json = String(data: data, encoding: .utf8) {
                serializedInput = json
            } else {
                serializedInput = "{}"
            }
        } else {
            serializedInput = "{}"
        }

        return "\(sessionId):\(toolName ?? "unknown"):\(serializedInput)"
    }

    // MARK: - History Loading (for UI)

    /// Request history load for a session
    func loadHistory(sessionId: String, cwd: String) {
        Task {
            await sessionStore.process(.loadHistory(sessionId: sessionId, cwd: cwd))
        }
    }
    
    deinit {
        cancellables.removeAll()
    }
}

extension ClaudeSessionMonitor: HookMonitorLifecycleControlling {}

// MARK: - Interrupt Watcher Delegate

extension ClaudeSessionMonitor: JSONLInterruptWatcherDelegate {
    nonisolated func didDetectInterrupt(sessionId: String) {
        Task { [weak self] in
            await self?.sessionStore.process(.interruptDetected(sessionId: sessionId))
        }

        Task { @MainActor in
            InterruptWatcherManager.shared.stopWatching(sessionId: sessionId)
        }
    }
}
