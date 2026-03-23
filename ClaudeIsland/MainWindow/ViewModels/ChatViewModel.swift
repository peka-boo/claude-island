//
//  ChatViewModel.swift
//  ClaudeIsland
//
//  ViewModel for the chat content area.
//  Manages message display, sending, streaming, and CLI session lifecycle.
//

import Foundation
import SwiftData
import os.log

private let logger = Logger(subsystem: "com.claudeisland", category: "Chat")

// MARK: - ChatViewModel

@Observable
@MainActor
final class ChatViewModel {
    private struct QueuedInteractiveResponse: Sendable {
        let prompt: String
        let cliSessionId: String?
    }

    // MARK: - State

    var messages: [MessageDTO] = []
    var inputText: String = ""
    var isProcessing = false
    var isStreaming = false
    var hasOlderMessages = false
    var isLoadingOlderMessages = false
    var currentStreamingText: String = ""
    var currentThinkingText: String = ""
    var currentThreadId: String?
    var threadInfo: ThreadDTO?
    var currentProjectPath: String?
    var structuredHistory: StructuredHistorySnapshot = .empty
    var availableCommands: [ComposerCommandSuggestion] = SessionCommandCatalog.load(cwd: nil)
    var localPendingPermission: LocalCLIPermissionRequest?
    var error: String?

    // MARK: - Dependencies

    private var dataActor: BackgroundDataActor?
    private let cliManager: CLISessionManager
    private var permissionFallbackTracker = CLIPermissionFallbackTracker()
    private var lastSubmittedPrompt: String?
    private var queuedApprovedRetry: LocalCLIPermissionRequest?
    private var queuedInteractiveResponse: QueuedInteractiveResponse?
    private var loadedMessageCount = 0
    private var structuredHistoryVisibleCount = 0
    private var structuredHistoryLoadTask: Task<Void, Never>?
    private var loadedStructuredHistoryKey: String?

    init(cliManager: CLISessionManager) {
        self.cliManager = cliManager
    }

    func configure(with container: ModelContainer) {
        self.dataActor = BackgroundDataActor(modelContainer: container)
    }

    // MARK: - Load Messages

    func loadThread(_ threadId: String) async {
        currentThreadId = threadId
        messages = []
        structuredHistory = .empty
        hasOlderMessages = false
        isLoadingOlderMessages = false
        currentStreamingText = ""
        currentThinkingText = ""
        error = nil
        localPendingPermission = nil
        permissionFallbackTracker.reset()
        queuedApprovedRetry = nil
        queuedInteractiveResponse = nil
        loadedMessageCount = 0
        structuredHistoryVisibleCount = 0
        loadedStructuredHistoryKey = nil
        structuredHistoryLoadTask?.cancel()
        structuredHistoryLoadTask = nil
        guard let actor = dataActor else { return }

        do {
            threadInfo = try await actor.fetchThread(threadId: threadId)
            currentProjectPath = try await resolveProjectPath(for: threadInfo, actor: actor)
            availableCommands = SessionCommandCatalog.load(cwd: currentProjectPath)
            try await refreshVisibleMessages(threadId: threadId, actor: actor)
            scheduleStructuredHistoryRefreshIfNeeded(preserveVisibleCount: false)
            isProcessing = await cliManager.isActive(threadId: threadId)
        } catch {
            logger.error("Failed to load thread: \(error)")
        }
    }

    // MARK: - Send Message

    func sendMessage() async {
        guard let threadId = currentThreadId,
              let actor = dataActor,
              let action = ComposerCommandLogic.submitAction(for: inputText) else {
            return
        }

        inputText = ""
        localPendingPermission = nil
        permissionFallbackTracker.reset()
        queuedApprovedRetry = nil
        queuedInteractiveResponse = nil

        switch action {
        case .local(let command):
            await handleLocalCommand(command, threadId: threadId, actor: actor)
            return

        case .send(let text):
            lastSubmittedPrompt = text
            isProcessing = true
            isStreaming = true
            currentStreamingText = ""
            currentThinkingText = ""
            error = nil

            do {
                _ = try await actor.appendMessage(
                    threadId: threadId,
                    role: .user,
                    content: text
                )

                await reloadThread(threadId)

                guard let thread = try await actor.fetchThread(threadId: threadId),
                      let projectId = thread.projectId,
                      let project = try await actor.fetchProject(projectId: projectId) else {
                    isProcessing = false
                    isStreaming = false
                    return
                }

                await setupStreamHandler(threadId: threadId)
                try await actor.updateThreadRuntime(threadId: threadId, status: .active)
                threadInfo = try await actor.fetchThread(threadId: threadId)

                switch ThreadSessionRouter.route(
                    isActiveProcess: await cliManager.isActive(threadId: threadId),
                    cliSessionId: thread.cliSessionId
                ) {
                case .sendToActiveProcess:
                    error = "Claude is still responding. Stop the current turn before sending another message."
                    isProcessing = false
                    isStreaming = false

                case .resumePersistedSession(let sessionId):
                    await cliManager.runTurn(
                        threadId: threadId,
                        cwd: project.path,
                        prompt: text,
                        cliSessionId: sessionId,
                        sessionName: thread.title,
                        permissionMode: .default
                    )

                case .startNewSession:
                    await cliManager.runTurn(
                        threadId: threadId,
                        cwd: project.path,
                        prompt: text,
                        cliSessionId: nil,
                        sessionName: thread.title,
                        permissionMode: .default
                    )
                }
            } catch {
                logger.error("Failed to send message: \(error)")
                self.error = "Failed to send message: \(error.localizedDescription)"
                isProcessing = false
                isStreaming = false
            }
        }
    }

    // MARK: - Interrupt

    func interrupt() async {
        guard let threadId = currentThreadId else { return }
        await cliManager.interruptSession(threadId: threadId)
    }

    func terminate() async {
        guard let threadId = currentThreadId else { return }

        await cliManager.stopSession(threadId: threadId)
        isProcessing = false
        isStreaming = false
        currentStreamingText = ""
        currentThinkingText = ""
        localPendingPermission = nil
        permissionFallbackTracker.reset()
        queuedApprovedRetry = nil
        queuedInteractiveResponse = nil

        guard let actor = dataActor else { return }
        try? await actor.updateThreadRuntime(threadId: threadId, status: .idle)
        await reloadThread(threadId)
    }

    func approveLocalPermissionFallback() async {
        guard let pending = localPendingPermission else { return }

        localPendingPermission = nil
        permissionFallbackTracker.clearPendingRequest()
        queuedApprovedRetry = pending
        error = nil

        guard let threadId = currentThreadId,
              let actor = dataActor else {
            queuedApprovedRetry = nil
            return
        }

        _ = try? await actor.appendMessage(
            threadId: threadId,
            role: .system,
            content: "Approved pending \(pending.toolName) request. Retrying now."
        )
        await reloadThread(threadId)

        if await cliManager.isActive(threadId: threadId) {
            return
        }

        await retryApprovedLocalPermissionIfNeeded()
    }

    func denyLocalPermissionFallback() async {
        guard localPendingPermission != nil else { return }

        let deniedToolName = localPendingPermission?.toolName ?? "tool"
        localPendingPermission = nil
        permissionFallbackTracker.clearPendingRequest()
        queuedApprovedRetry = nil

        guard let threadId = currentThreadId,
              let actor = dataActor else { return }

        _ = try? await actor.appendMessage(
            threadId: threadId,
            role: .system,
            content: "Denied pending \(deniedToolName) request."
        )
        await reloadThread(threadId)
    }

    func submitLocalInteractivePromptResponse(_ message: String) async -> Bool {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let pending = localPendingPermission,
              pending.toolName == "AskUserQuestion",
              dataActor != nil,
              let threadId = currentThreadId else {
            return false
        }

        localPendingPermission = nil
        permissionFallbackTracker.clearPendingRequest()
        error = nil

        queuedInteractiveResponse = QueuedInteractiveResponse(
            prompt: CLIPermissionFallbackTracker.makeAskUserQuestionFollowUpPrompt(trimmed),
            cliSessionId: normalizeCLISessionId(threadInfo?.cliSessionId) ?? pending.cliSessionId
        )

        if await cliManager.isActive(threadId: threadId) {
            return true
        }

        return await sendQueuedInteractiveResponseIfNeeded()
    }

    func loadOlderMessages() async {
        guard !isLoadingOlderMessages else { return }

        if isUsingStructuredHistory {
            let totalStructuredItems = structuredHistory.items.count
            guard structuredHistoryVisibleCount < totalStructuredItems else { return }

            isLoadingOlderMessages = true
            structuredHistoryVisibleCount = min(
                totalStructuredItems,
                structuredHistoryVisibleCount + ChatMessagePaginationSupport.defaultPageSize
            )
            isLoadingOlderMessages = false
            return
        }

        guard let actor = dataActor,
              let threadId = currentThreadId,
              let oldestMessage = messages.first else {
            return
        }

        isLoadingOlderMessages = true
        defer { isLoadingOlderMessages = false }

        do {
            let olderMessages = try await actor.fetchMessagesBefore(
                threadId: threadId,
                beforeMessageId: oldestMessage.id,
                beforeCreatedAt: oldestMessage.createdAt,
                limit: ChatMessagePaginationSupport.defaultPageSize
            )

            let merged = ChatMessagePaginationSupport.mergeOlderPage(
                existingItems: messages,
                olderItems: olderMessages,
                totalCount: threadInfo?.messageCount ?? loadedMessageCount
            )

            messages = merged.items
            loadedMessageCount = merged.loadedCount
            hasOlderMessages = merged.hasOlderItems
        } catch {
            logger.error("Failed to load older messages: \(error)")
        }
    }

    // MARK: - Stream Handling

    private func setupStreamHandler(threadId: String) async {
        await cliManager.setOnStreamEvent { [weak self] eventThreadId, event in
            guard eventThreadId == threadId else { return }
            Task { @MainActor in
                self?.handleStreamEvent(event)
            }
        }

        await cliManager.setOnProcessEnded { [weak self] endedThreadId in
            guard endedThreadId == threadId else { return }
            Task { @MainActor in
                self?.handleProcessEnded()
            }
        }
    }

    private func handleStreamEvent(_ event: CLIStreamEvent) {
        switch event {
        case .thinking(let text):
            currentThinkingText = text

        case .text(let text):
            currentStreamingText += text

        case .toolUse(_, let name, let input):
            permissionFallbackTracker.consume(
                event,
                originalPrompt: lastSubmittedPrompt ?? "",
                cliSessionId: threadInfo?.cliSessionId
            )
            localPendingPermission = permissionFallbackTracker.pendingRequest

            // Save tool use as a message
            Task {
                guard let actor = dataActor, let threadId = currentThreadId else { return }
                _ = try? await actor.appendMessage(
                    threadId: threadId,
                    role: .assistant,
                    content: "Using tool: \(name)",
                    toolName: name,
                    toolInput: input
                )
                await reloadThread(threadId)
            }

        case .toolResult(_, _, let output):
            permissionFallbackTracker.consume(
                event,
                originalPrompt: lastSubmittedPrompt ?? "",
                cliSessionId: threadInfo?.cliSessionId
            )
            localPendingPermission = permissionFallbackTracker.pendingRequest

            Task {
                guard let actor = dataActor, let threadId = currentThreadId else { return }
                _ = try? await actor.appendMessage(
                    threadId: threadId,
                    role: .assistant,
                    content: "",
                    toolResult: output
                )
                await reloadThread(threadId)
            }

        case .result(let info):
            // Save the final assistant message
            Task {
                guard let actor = dataActor, let threadId = currentThreadId else { return }

                let assistantText = currentStreamingText.isEmpty ? info.result : currentStreamingText

                if !assistantText.isEmpty {
                    _ = try? await actor.appendMessage(
                        threadId: threadId,
                        role: .assistant,
                        content: assistantText,
                        thinking: currentThinkingText.isEmpty ? nil : currentThinkingText,
                        costUsd: info.costUsd,
                        tokensIn: info.tokensIn,
                        tokensOut: info.tokensOut
                    )
                }

                try? await actor.updateThreadRuntime(
                    threadId: threadId,
                    status: .active,
                    cliSessionId: info.sessionId
                )
                await reloadThread(threadId)
                currentStreamingText = ""
                currentThinkingText = ""
                isProcessing = false
                isStreaming = false
                if localPendingPermission == nil {
                    if await sendQueuedInteractiveResponseIfNeeded() {
                        return
                    }
                    await retryApprovedLocalPermissionIfNeeded()
                }
            }

        case .sessionStart(let sessionId):
            logger.info("Session started: \(sessionId)")
            persistSessionIdentity(sessionId, for: currentThreadId)

        case .error(let message):
            error = message
            isProcessing = false
            isStreaming = false

        case .unknown:
            break
        }
    }

    private func handleProcessEnded() {
        isProcessing = false
        isStreaming = false
        currentStreamingText = ""
        currentThinkingText = ""

        // Reload messages to get final state
        Task {
            guard let actor = dataActor, let threadId = currentThreadId else { return }
            try? await actor.updateThreadRuntime(threadId: threadId, status: .idle)
            await reloadThread(threadId)
            if await sendQueuedInteractiveResponseIfNeeded() {
                return
            }
            await retryApprovedLocalPermissionIfNeeded()
        }
    }

    private func reloadThread(_ threadId: String) async {
        guard let actor = dataActor else { return }

        do {
            threadInfo = try await actor.fetchThread(threadId: threadId)
            currentProjectPath = try await resolveProjectPath(for: threadInfo, actor: actor)
            availableCommands = SessionCommandCatalog.load(cwd: currentProjectPath)
            try await refreshVisibleMessages(threadId: threadId, actor: actor)
            scheduleStructuredHistoryRefreshIfNeeded(preserveVisibleCount: true)
        } catch {
            logger.error("Failed to reload thread \(threadId): \(error)")
        }
    }

    private func persistSessionIdentity(_ sessionId: String, for threadId: String?) {
        guard let actor = dataActor,
              let threadId,
              let normalizedSessionId = normalizeCLISessionId(sessionId) else {
            return
        }

        Task {
            try? await actor.updateThreadRuntime(
                threadId: threadId,
                status: .active,
                cliSessionId: normalizedSessionId
            )

            if threadId == currentThreadId {
                threadInfo = try? await actor.fetchThread(threadId: threadId)
                currentProjectPath = try? await resolveProjectPath(for: threadInfo, actor: actor)
                availableCommands = SessionCommandCatalog.load(cwd: currentProjectPath)
                scheduleStructuredHistoryRefreshIfNeeded(preserveVisibleCount: true)
            }
        }
    }

    private func retryApprovedLocalPermissionIfNeeded() async {
        guard let pending = queuedApprovedRetry,
              let actor = dataActor,
              let threadId = currentThreadId else {
            return
        }

        guard let thread = try? await actor.fetchThread(threadId: threadId),
              let projectId = thread.projectId,
              let project = try? await actor.fetchProject(projectId: projectId) else {
            queuedApprovedRetry = nil
            return
        }

        guard !(await cliManager.isActive(threadId: threadId)) else {
            return
        }

        queuedApprovedRetry = nil
        lastSubmittedPrompt = pending.retryPrompt
        isProcessing = true
        isStreaming = true
        currentStreamingText = ""
        currentThinkingText = ""
        error = nil

        await setupStreamHandler(threadId: threadId)
        try? await actor.updateThreadRuntime(threadId: threadId, status: .active)
        threadInfo = try? await actor.fetchThread(threadId: threadId)

        await cliManager.runTurn(
            threadId: threadId,
            cwd: project.path,
            prompt: pending.retryPrompt,
            cliSessionId: normalizeCLISessionId(thread.cliSessionId) ?? pending.cliSessionId,
            sessionName: thread.title,
            permissionMode: .bypassPermissions
        )
    }

    private func sendQueuedInteractiveResponseIfNeeded() async -> Bool {
        guard let queued = queuedInteractiveResponse,
              let actor = dataActor,
              let threadId = currentThreadId else {
            return false
        }

        guard let thread = try? await actor.fetchThread(threadId: threadId),
              let projectId = thread.projectId,
              let project = try? await actor.fetchProject(projectId: projectId) else {
            queuedInteractiveResponse = nil
            return false
        }

        guard !(await cliManager.isActive(threadId: threadId)) else {
            return false
        }

        queuedInteractiveResponse = nil
        lastSubmittedPrompt = queued.prompt
        isProcessing = true
        isStreaming = true
        currentStreamingText = ""
        currentThinkingText = ""
        error = nil

        await setupStreamHandler(threadId: threadId)
        try? await actor.updateThreadRuntime(threadId: threadId, status: .active)
        threadInfo = try? await actor.fetchThread(threadId: threadId)

        let cliSessionId = normalizeCLISessionId(thread.cliSessionId) ?? queued.cliSessionId
        switch ThreadSessionRouter.route(
            isActiveProcess: false,
            cliSessionId: cliSessionId
        ) {
        case .sendToActiveProcess:
            return false

        case .resumePersistedSession(let sessionId):
            await cliManager.runTurn(
                threadId: threadId,
                cwd: project.path,
                prompt: queued.prompt,
                cliSessionId: sessionId,
                sessionName: thread.title,
                permissionMode: .default
            )

        case .startNewSession:
            await cliManager.runTurn(
                threadId: threadId,
                cwd: project.path,
                prompt: queued.prompt,
                cliSessionId: nil,
                sessionName: thread.title,
                permissionMode: .default
            )
        }

        return true
    }

    func renameCurrentThread(to title: String) async {
        guard let actor = dataActor,
              let threadId = currentThreadId else { return }

        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        do {
            try await actor.updateThreadTitle(threadId: threadId, title: trimmed)
            await reloadThread(threadId)
        } catch {
            logger.error("Failed to rename thread: \(error)")
            self.error = "Failed to rename thread: \(error.localizedDescription)"
        }
    }

    var isUsingStructuredHistory: Bool {
        guard let source = threadInfo?.source else { return false }
        switch source {
        case .imported, .takeover:
            return !structuredHistory.items.isEmpty
        case .app:
            return false
        }
    }

    var displayedStructuredItems: [ChatHistoryItem] {
        guard isUsingStructuredHistory else { return [] }

        let cutoff = structuredHistory.items.last?.timestamp ?? .distantPast
        let visibleCount = min(
            structuredHistory.items.count,
            max(
                structuredHistoryVisibleCount,
                ChatMessagePaginationSupport.initialVisibleCount(totalCount: structuredHistory.items.count)
            )
        )
        var items = Array(structuredHistory.items.suffix(visibleCount))

        for message in messages where message.createdAt > cutoff.addingTimeInterval(0.05) {
            switch message.role {
            case .user:
                items.append(
                    ChatHistoryItem(
                        id: "db-\(message.id)",
                        type: .user(message.content),
                        timestamp: message.createdAt
                    )
                )

            case .assistant:
                if let thinking = message.thinking, !thinking.isEmpty {
                    items.append(
                        ChatHistoryItem(
                            id: "db-\(message.id)-thinking",
                            type: .thinking(thinking),
                            timestamp: message.createdAt
                        )
                    )
                }

                if !message.content.isEmpty {
                    items.append(
                        ChatHistoryItem(
                            id: "db-\(message.id)-assistant",
                            type: .assistant(message.content),
                            timestamp: message.createdAt
                        )
                    )
                }

            case .system:
                continue
            }
        }

        return items.sorted { $0.timestamp < $1.timestamp }
    }

    var hasOlderTranscriptItems: Bool {
        if isUsingStructuredHistory {
            return structuredHistoryVisibleCount < structuredHistory.items.count
        }

        return hasOlderMessages
    }

    private func resolveProjectPath(for thread: ThreadDTO?, actor: BackgroundDataActor) async throws -> String? {
        guard let projectId = thread?.projectId else { return nil }
        return try await actor.fetchProject(projectId: projectId)?.path
    }

    private func refreshVisibleMessages(
        threadId: String,
        actor: BackgroundDataActor,
        desiredCount: Int? = nil
    ) async throws {
        let totalCount = threadInfo?.messageCount ?? 0
        let requestedCount = max(
            ChatMessagePaginationSupport.defaultPageSize,
            desiredCount ?? loadedMessageCount
        )
        let visibleCount = ChatMessagePaginationSupport.initialVisibleCount(
            totalCount: totalCount,
            pageSize: requestedCount
        )

        if visibleCount == 0 {
            messages = []
            loadedMessageCount = 0
            hasOlderMessages = false
            lastSubmittedPrompt = nil
            return
        }

        let recentMessages = try await actor.fetchRecentMessages(
            threadId: threadId,
            limit: visibleCount
        )
        let paginationState = ChatMessagePaginationSupport.state(
            totalCount: totalCount,
            loadedItems: recentMessages.count
        )

        messages = recentMessages
        loadedMessageCount = paginationState.loadedCount
        hasOlderMessages = paginationState.hasOlderItems
        lastSubmittedPrompt = recentMessages.last(where: { message in
            message.role == .user &&
            message.toolName == nil &&
            message.toolResult == nil &&
            !message.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        })?.content
    }

    private func scheduleStructuredHistoryRefreshIfNeeded(preserveVisibleCount: Bool) {
        guard let thread = threadInfo,
              let sessionId = normalizeCLISessionId(thread.cliSessionId),
              let projectPath = currentProjectPath else {
            structuredHistoryLoadTask?.cancel()
            structuredHistoryLoadTask = nil
            loadedStructuredHistoryKey = nil
            structuredHistory = .empty
            structuredHistoryVisibleCount = 0
            return
        }

        switch thread.source {
        case .imported, .takeover:
            let loadKey = "\(projectPath)|\(sessionId)"
            guard structuredHistory.items.isEmpty || loadedStructuredHistoryKey != loadKey else {
                return
            }

            let threadId = thread.id
            let previousVisibleCount = preserveVisibleCount ? structuredHistoryVisibleCount : 0
            structuredHistoryLoadTask?.cancel()
            structuredHistoryLoadTask = Task { [weak self] in
                let snapshot = await StructuredHistorySnapshotBuilder.load(
                    sessionId: sessionId,
                    cwd: projectPath
                )

                guard !Task.isCancelled else { return }

                await MainActor.run {
                    guard let self,
                          self.currentThreadId == threadId,
                          normalizeCLISessionId(self.threadInfo?.cliSessionId) == sessionId,
                          self.currentProjectPath == projectPath else {
                        return
                    }

                    self.structuredHistory = snapshot
                    self.loadedStructuredHistoryKey = loadKey
                    self.structuredHistoryVisibleCount = min(
                        snapshot.items.count,
                        max(
                            previousVisibleCount,
                            ChatMessagePaginationSupport.initialVisibleCount(totalCount: snapshot.items.count)
                        )
                    )
                }
            }
        case .app:
            structuredHistoryLoadTask?.cancel()
            structuredHistoryLoadTask = nil
            loadedStructuredHistoryKey = nil
            structuredHistory = .empty
            structuredHistoryVisibleCount = 0
        }
    }

    private func handleLocalCommand(
        _ command: ComposerLocalCommand,
        threadId: String,
        actor: BackgroundDataActor
    ) async {
        do {
            switch command {
            case .help:
                _ = try await actor.appendMessage(
                    threadId: threadId,
                    role: .assistant,
                    content: SessionCommandCatalog.helpMarkdown
                )
                await reloadThread(threadId)

            case .clear:
                await cliManager.stopSession(threadId: threadId)
                currentStreamingText = ""
                currentThinkingText = ""
                isProcessing = false
                isStreaming = false
                error = nil
                structuredHistory = .empty
                structuredHistoryVisibleCount = 0
                loadedStructuredHistoryKey = nil
                try await actor.clearThreadConversation(threadId: threadId)
                await reloadThread(threadId)

            case .rename(let title):
                try await actor.updateThreadTitle(threadId: threadId, title: title)
                await reloadThread(threadId)
            }
        } catch {
            logger.error("Failed to handle local composer command: \(error)")
            self.error = "Failed to run command: \(error.localizedDescription)"
        }
    }
}
