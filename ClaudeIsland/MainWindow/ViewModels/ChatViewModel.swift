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
    var availableCommands: [ComposerCommandSuggestion] = []
    var localPendingPermission: LocalCLIPermissionRequest?
    var error: String?

    // MARK: - Dependencies

    private var dataActor: BackgroundDataActor?
    private let cliManager: CLIManaging
    private var permissionFallbackTracker = CLIPermissionFallbackTracker()
    private var lastSubmittedPrompt: String?
    private var queuedApprovedRetry: LocalCLIPermissionRequest?
    private var queuedInteractiveResponse: QueuedInteractiveResponse?
    private var loadedMessageCount = 0
    private var structuredHistoryVisibleCount = 0
    private var structuredHistoryLoadTask: Task<Void, Never>?
    private var loadedStructuredHistoryKey: String?
    private var streamingResponseBuffer = StreamingResponseBuffer()
    private var pendingThinkingText: String?
    private var streamingFlushTask: Task<Void, Never>?
    
    // 预加载相关属性
    private var preloadTask: Task<Void, Never>?
    private var isPreloading = false
    private var lastPreloadTime: Date?
    private let preloadThreshold: Double = 0.8 // 当滚动到80%位置时触发预加载
    
    // 页面缓存相关属性
    private var messagePageCache: [String: [MessageDTO]] = [:] // 键：beforeMessageId，值：消息页面
    private let maxCacheSize = 10 // 最大缓存页面数
    private var cacheAccessOrder: [String] = [] // LRU访问顺序

    init(cliManager: CLIManaging) {
        self.cliManager = cliManager
        // Load commands in background to avoid blocking main thread
        loadCommandsInBackground()
    }

    private func loadCommandsInBackground(cwd: String? = nil) {
        Task.detached(priority: .background) { [weak self] in
            let commands = SessionCommandCatalog.load(cwd: cwd)
            await MainActor.run { [weak self] in
                self?.availableCommands = commands
            }
        }
    }

    private func loadCommandsInBackground(path: String) {
        loadCommandsInBackground(cwd: path)
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
        resetStreamingState()
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

        // Clear cache
        clearCache()

        // Reset conversation parser state for the previous session
        if let previousSessionId = threadInfo?.cliSessionId.flatMap({ normalizeCLISessionId($0) }) {
            Task.detached(priority: .background) {
                await ConversationParser.shared.resetState(for: previousSessionId)
            }
        }

        guard let actor = dataActor else { return }

        do {
            threadInfo = try await actor.fetchThread(threadId: threadId)
            let resolvedPath = try await resolveProjectPath(for: threadInfo, actor: actor)
            currentProjectPath = resolvedPath
            loadCommandsInBackground(cwd: currentProjectPath)
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
            resetStreamingState()
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
        resetStreamingState()
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
            // 使用动态页面大小
            let dynamicPageSize = messages.isEmpty ? 
                ChatMessagePaginationSupport.defaultPageSize :
                ChatMessagePaginationSupport.dynamicPageSize(for: messages)
            
            structuredHistoryVisibleCount = min(
                totalStructuredItems,
                structuredHistoryVisibleCount + dynamicPageSize
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
            // 首先检查缓存
            if let cachedMessages = getCachedPage(beforeMessageId: oldestMessage.id) {
                logger.info("Using cached messages for page before: \(oldestMessage.id)")
                
                let merged = ChatMessagePaginationSupport.mergeOlderPage(
                    existingItems: messages,
                    olderItems: cachedMessages,
                    totalCount: threadInfo?.messageCount ?? loadedMessageCount
                )
                
                messages = merged.items
                loadedMessageCount = merged.loadedCount
                hasOlderMessages = merged.hasOlderItems
                return
            }
            
            // 使用动态页面大小，基于已加载消息的平均长度
            let dynamicPageSize = ChatMessagePaginationSupport.dynamicPageSize(for: messages)
            
            let olderMessages = try await actor.fetchMessagesBefore(
                threadId: threadId,
                beforeMessageId: oldestMessage.id,
                beforeCreatedAt: oldestMessage.createdAt,
                limit: dynamicPageSize
            )
            
            // 缓存加载的消息
            cachePage(olderMessages, beforeMessageId: oldestMessage.id)

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
    
    /// 检查是否需要预加载更多消息
    /// - Parameter scrollPosition: 当前滚动位置（0.0到1.0）
    func checkPreloadIfNeeded(scrollPosition: Double) {
        guard hasOlderMessages, 
              !isLoadingOlderMessages, 
              !isPreloading,
              scrollPosition <= preloadThreshold else { return }
        
        // 防抖：确保至少间隔1秒
        if let lastTime = lastPreloadTime {
            let elapsed = Date().timeIntervalSince(lastTime)
            guard elapsed > 1.0 else { return }
        }
        
        preloadTask?.cancel()
        preloadTask = Task { [weak self] in
            guard let self, !Task.isCancelled else { return }
            
            self.isPreloading = true
            defer { 
                self.isPreloading = false
                self.lastPreloadTime = Date()
            }
            
            // 使用较小的预加载页面大小
            let preloadPageSize = messages.isEmpty ? 
                ChatMessagePaginationSupport.defaultPageSize / 2 :
                ChatMessagePaginationSupport.preloadPageSize(
                    averageMessageLength: Double(messages.reduce(0) { $0 + $1.content.count }) / Double(messages.count)
                )
            
            // 模拟预加载延迟，避免频繁加载
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5秒
            
            guard !Task.isCancelled else { return }
            
            // 实际加载逻辑会在滚动到底部时触发
            // 这里只是设置预加载标志，真正的加载由loadOlderMessages处理
            logger.info("Preload triggered with page size: \(preloadPageSize)")
        }
    }
    
    // MARK: - 页面缓存管理
    
    /// 从缓存获取消息页面
    /// - Parameter beforeMessageId: 在此消息之前的消息ID
    /// - Returns: 缓存的消息数组，如果未缓存则返回nil
    private func getCachedPage(beforeMessageId: String) -> [MessageDTO]? {
        guard let cached = messagePageCache[beforeMessageId] else { return nil }
        
        // 更新访问顺序（LRU）
        cacheAccessOrder.removeAll { $0 == beforeMessageId }
        cacheAccessOrder.append(beforeMessageId)
        
        logger.info("Cache hit for page before message: \(beforeMessageId)")
        return cached
    }
    
    /// 将消息页面添加到缓存
    /// - Parameters:
    ///   - messages: 消息数组
    ///   - beforeMessageId: 在此消息之前的消息ID
    private func cachePage(_ messages: [MessageDTO], beforeMessageId: String) {
        // 如果缓存已满，移除最久未使用的页面
        if messagePageCache.count >= maxCacheSize, let oldestKey = cacheAccessOrder.first {
            messagePageCache.removeValue(forKey: oldestKey)
            cacheAccessOrder.removeFirst()
            logger.info("Cache eviction for key: \(oldestKey)")
        }
        
        messagePageCache[beforeMessageId] = messages
        cacheAccessOrder.append(beforeMessageId)
        logger.info("Cached page with \(messages.count) messages before message: \(beforeMessageId)")
    }
    
    /// 清空缓存
    private func clearCache() {
        messagePageCache.removeAll()
        cacheAccessOrder.removeAll()
        logger.info("Message cache cleared")
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
            updateThinkingText(text)

        case .text(let text):
            appendStreamingText(text)

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
            flushPendingStreamUpdatesImmediately()

            // Save the final assistant message
            Task {
                guard let actor = dataActor, let threadId = currentThreadId else { return }

                let assistantText = streamingResponseBuffer.resolvedText(fallback: info.result)

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
                resetStreamingState()
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
            flushPendingStreamUpdatesImmediately()
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
        resetStreamingState()

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
            // Load commands in background to avoid blocking main thread
            loadCommandsInBackground(cwd: currentProjectPath)
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
                // Load commands in background to avoid blocking main thread
                loadCommandsInBackground(cwd: currentProjectPath)
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
        resetStreamingState()
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
        resetStreamingState()
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
        
        // 在加载消息后，计算动态页面大小用于后续预加载
        if !messages.isEmpty {
            let dynamicPageSize = ChatMessagePaginationSupport.dynamicPageSize(for: messages)
            logger.info("Calculated dynamic page size: \(dynamicPageSize) based on average message length")
        }
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
            structuredHistoryLoadTask = Task.detached(priority: .background) { [weak self] in
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
                    let threadSource = self.threadInfo?.source
                    logger.info("[UI] Loaded structured history: \(snapshot.items.count) items, threadSource: \(String(describing: threadSource))")
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

    private func appendStreamingText(_ text: String) {
        streamingResponseBuffer.append(text)
        scheduleStreamingFlushIfNeeded()
    }

    private func updateThinkingText(_ text: String) {
        guard !text.isEmpty else { return }
        pendingThinkingText = text
        scheduleStreamingFlushIfNeeded()
    }

    private func scheduleStreamingFlushIfNeeded() {
        guard streamingFlushTask == nil else { return }

        streamingFlushTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: StreamingResponseBuffer.flushIntervalNanoseconds)
            guard !Task.isCancelled else { return }
            self?.flushPendingStreamUpdates()
        }
    }

    private func flushPendingStreamUpdates() {
        streamingFlushTask = nil

        if let pendingThinkingText {
            currentThinkingText = pendingThinkingText
            self.pendingThinkingText = nil
        }

        if streamingResponseBuffer.flush() {
            currentStreamingText = streamingResponseBuffer.committedText
        }
    }

    private func flushPendingStreamUpdatesImmediately() {
        streamingFlushTask?.cancel()
        streamingFlushTask = nil
        flushPendingStreamUpdates()
    }

    private func resetStreamingState() {
        streamingFlushTask?.cancel()
        streamingFlushTask = nil
        pendingThinkingText = nil
        streamingResponseBuffer.reset()
        currentStreamingText = ""
        currentThinkingText = ""
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
                resetStreamingState()
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
