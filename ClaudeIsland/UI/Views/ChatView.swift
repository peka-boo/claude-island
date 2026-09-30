//
//  ChatView.swift
//  ClaudeIsland
//
//  Redesigned chat interface with clean visual hierarchy
//

import Combine
import SwiftUI

struct ChatView: View {
    let sessionId: String
    let initialSession: SessionState
    let sessionMonitor: ClaudeSessionMonitor
    @ObservedObject var viewModel: NotchViewModel

    @State private var inputText: String = ""
    @State private var history: [ChatHistoryItem] = []
    @State private var session: SessionState
    @State private var isLoading: Bool = true
    @State private var hasLoadedOnce: Bool = false
    @State private var shouldScrollToBottom: Bool = false
    @State private var isAutoscrollPaused: Bool = false
    @State private var newMessageCount: Int = 0
    @State private var previousHistoryCount: Int = 0
    @State private var isBottomVisible: Bool = true
    @State private var isSendingMessage: Bool = false
    @State private var messageSendError: String?
    @State private var interactiveReplyDraft: String = ""
    @State private var isSendingInteractiveReply: Bool = false
    @State private var interactiveReplyError: String?
    @FocusState private var isInputFocused: Bool

    init(sessionId: String, initialSession: SessionState, sessionMonitor: ClaudeSessionMonitor, viewModel: NotchViewModel) {
        self.sessionId = sessionId
        self.initialSession = initialSession
        self.sessionMonitor = sessionMonitor
        self._viewModel = ObservedObject(wrappedValue: viewModel)
        self._session = State(initialValue: initialSession)

        // Initialize from cache if available (prevents loading flicker on view recreation)
        let cachedHistory = ChatHistoryManager.shared.history(for: sessionId)
        let alreadyLoaded = !cachedHistory.isEmpty
        self._history = State(initialValue: cachedHistory)
        self._isLoading = State(initialValue: !alreadyLoaded)
        self._hasLoadedOnce = State(initialValue: alreadyLoaded)
    }

    /// Whether we're waiting for approval
    private var isWaitingForApproval: Bool {
        session.phase.isWaitingForApproval
    }

    /// Extract the tool name if waiting for approval
    private var approvalTool: String? {
        session.phase.approvalToolName
    }

    private var currentPermission: PermissionContext? {
        session.activePermission
    }

    private var currentPermissionId: String? {
        currentPermission?.toolUseId
    }

    private var currentPermissionFormattedInput: String? {
        currentPermission?.formattedInput
    }

    private var currentPermissionRawInput: [String: Any]? {
        currentPermission?.toolInput?.mapValues(\.value)
    }

    private var interactivePromptPresentation: InteractivePromptPresentation? {
        InteractivePromptDisplaySupport.presentation(
            toolName: approvalTool,
            rawInput: currentPermissionRawInput
        )
    }

    
    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                // Header
                ChatHeaderView(sessionTitle: session.displayTitle, onBack: { viewModel.exitChat() })

                // Messages
                if isLoading {
                    loadingState
                } else if history.isEmpty {
                    emptyState
                } else {
                    messageList
                }

                // Approval bar, interactive prompt, or Input bar
                if let tool = approvalTool {
                    if tool == "AskUserQuestion" {
                        interactivePromptBar
                            .id(currentPermissionId ?? "interactive-prompt")
                            .transition(.asymmetric(
                                insertion: .opacity.combined(with: .move(edge: .bottom)),
                                removal: .opacity
                            ))
                    } else {
                        approvalBar(tool: tool)
                            .transition(.asymmetric(
                                insertion: .opacity.combined(with: .move(edge: .bottom)),
                                removal: .opacity
                            ))
                    }
                } else {
                    inputBar
                        .transition(.opacity)
                }
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: isWaitingForApproval)
        .animation(nil, value: viewModel.status)
        .task {
            // Skip if already loaded (prevents redundant work on view recreation)
            guard !hasLoadedOnce else { return }
            hasLoadedOnce = true

            // Check if already loaded (from previous visit)
            if ChatHistoryManager.shared.isLoaded(sessionId: sessionId) {
                history = ChatHistoryManager.shared.history(for: sessionId)
                isLoading = false
                return
            }

            // Load in background, show loading state
            await ChatHistoryManager.shared.loadFromFile(sessionId: sessionId, cwd: session.cwd)
            history = ChatHistoryManager.shared.history(for: sessionId)

            withAnimation(.easeOut(duration: 0.2)) {
                isLoading = false
            }
        }
        .onReceive(ChatHistoryManager.shared.$histories) { histories in
            // Update when count changes, last item differs, or content changes (e.g., tool status)
            if let newHistory = histories[sessionId] {
                let countChanged = newHistory.count != history.count
                let lastItemChanged = newHistory.last?.id != history.last?.id
                // Always update - the @Published ensures we only get notified on real changes
                // This allows tool status updates (waitingForApproval -> running) to reflect
                if countChanged || lastItemChanged || newHistory != history {
                    // Track new messages when autoscroll is paused
                    if isAutoscrollPaused && newHistory.count > previousHistoryCount {
                        let addedCount = newHistory.count - previousHistoryCount
                        newMessageCount += addedCount
                        previousHistoryCount = newHistory.count
                    }

                    history = newHistory

                    // Auto-scroll to bottom only if autoscroll is NOT paused
                    if !isAutoscrollPaused && countChanged {
                        shouldScrollToBottom = true
                    }

                    // If we have data, skip loading state (handles view recreation)
                    if isLoading && !newHistory.isEmpty {
                        isLoading = false
                    }
                }
            } else if hasLoadedOnce {
                // Session was loaded but is now gone (removed via /clear) - navigate back
                viewModel.exitChat()
            }
        }
        .onReceive(sessionMonitor.$instances) { sessions in
            if let updated = sessions.first(where: { $0.sessionId == sessionId }),
               updated != session {
                // Check if permission was just accepted (transition from waitingForApproval to processing)
                let wasWaiting = isWaitingForApproval
                session = updated
                let isNowProcessing = updated.phase == .processing

                if wasWaiting && isNowProcessing {
                    // Scroll to bottom after permission accepted (with slight delay)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        shouldScrollToBottom = true
                    }
                }
            }
        }
        .onChange(of: canSendMessages) { _, canSend in
            // Auto-focus input when this session becomes messageable.
            if canSend && !isInputFocused {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    isInputFocused = true
                }
            }
        }
        .onChange(of: currentPermissionId) { _, _ in
            interactiveReplyDraft = ""
            interactiveReplyError = nil
            isSendingInteractiveReply = false
        }
        .onAppear {
            // Auto-focus input when chat opens and messaging is available.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                if canSendMessages {
                    isInputFocused = true
                }
            }
        }
    }

    // MARK: - Header
    
    // Header view moved to ChatHeaderView.swift

    /// Whether the session is currently processing
    private var isProcessing: Bool {
        session.phase == .processing || session.phase == .compacting
    }

    /// Get the last user message ID for stable text selection per turn
    private var lastUserMessageId: String {
        for item in history.reversed() {
            if case .user = item.type {
                return item.id
            }
        }
        return ""
    }

    // MARK: - Loading State

    private var loadingState: some View {
        VStack(spacing: 8) {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: .white.opacity(0.4)))
                .scaleEffect(0.8)
            Text("Loading messages...")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white.opacity(0.4))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 24))
                .foregroundColor(.white.opacity(0.2))
            Text("No messages yet")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white.opacity(0.4))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Message List

    /// Background color for fade gradients
    private let fadeColor = Color(red: 0.00, green: 0.00, blue: 0.00)

    private var messageList: some View {
        MessageListView(
            history: history,
            isProcessing: isProcessing,
            lastUserMessageId: lastUserMessageId,
            sessionId: sessionId,
            isAutoscrollPaused: $isAutoscrollPaused,
            newMessageCount: $newMessageCount,
            shouldScrollToBottom: $shouldScrollToBottom,
            previousHistoryCount: previousHistoryCount,
            pauseAutoscroll: pauseAutoscroll,
            resumeAutoscroll: resumeAutoscroll
        )
    }

    // MARK: - Input Bar

    private var messageTransport: SessionMessageTransport {
        SessionMessageTransportSupport.transport(
            isInTmux: session.isInTmux,
            tty: session.tty,
            sessionId: session.sessionId,
            allowsDetachedResume: true
        )
    }

    /// Whether this session currently supports sending follow-up messages.
    private var canSendMessages: Bool {
        SessionMessageTransportSupport.canSendMessages(
            isInTmux: session.isInTmux,
            tty: session.tty,
            sessionId: session.sessionId,
            allowsDetachedResume: true
        )
    }

    private var inputBar: some View {
        InputBarView(
            messageSendError: messageSendError,
            messageTransport: messageTransport,
            canSendMessages: canSendMessages,
            inputText: $inputText,
            isInputFocused: $isInputFocused,
            isSendingMessage: isSendingMessage,
            isProcessing: isProcessing,
            sendMessage: { sendMessage() },
            interruptSession: { interruptSession() }
        )
    }

    // MARK: - Approval Bar

    private func approvalBar(tool: String) -> some View {
        ChatApprovalBar(
            tool: tool,
            toolInput: session.pendingToolInput,
            onApprove: { approvePermission() },
            onDeny: { denyPermission() }
        )
    }

    // MARK: - Interactive Prompt Bar

    /// Bar for interactive tools like AskUserQuestion that need terminal input
    private var interactivePromptBar: some View {
        Group {
            switch interactivePromptPresentation {
            case .structuredAsk(let prompt):
                ChatStructuredInteractivePromptBar(
                    prompt: prompt,
                    isSending: isSendingInteractiveReply,
                    errorMessage: interactiveReplyError,
                    onSubmit: submitStructuredPromptResponse
                )
            case .freeformAsk, .none:
                ChatInteractivePromptBar(
                    toolInput: currentPermissionFormattedInput,
                    replyText: $interactiveReplyDraft,
                    isSending: isSendingInteractiveReply,
                    errorMessage: interactiveReplyError,
                    onSubmit: submitInteractivePromptResponse,
                    onGoToTerminal: { focusTerminal() }
                )
            }
        }
    }

    // MARK: - Autoscroll Management

    /// Pause autoscroll (user scrolled away from bottom)
    private func pauseAutoscroll() {
        isAutoscrollPaused = true
        previousHistoryCount = history.count
    }

    /// Resume autoscroll and reset new message count
    private func resumeAutoscroll() {
        isAutoscrollPaused = false
        newMessageCount = 0
        previousHistoryCount = history.count
    }

    // MARK: - Actions

    private func focusTerminal() {
        Task {
            if let pid = session.pid {
                _ = await YabaiController.shared.focusWindow(forClaudePid: pid)
            } else {
                _ = await YabaiController.shared.focusWindow(forWorkingDirectory: session.cwd)
            }
        }
    }

    private func approvePermission() {
        sessionMonitor.approvePermission(sessionId: sessionId)
    }

    private func denyPermission() {
        sessionMonitor.denyPermission(sessionId: sessionId, reason: nil)
    }

    private func submitInteractivePromptResponse() {
        let trimmed = interactiveReplyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        sendInteractiveResponse(trimmed) {
            interactiveReplyDraft = ""
        }
    }

    private func submitStructuredPromptResponse(_ submission: AskUserQuestionSubmission) {
        sendInteractiveResponse(submission.responseText)
    }

    private func sendInteractiveResponse(_ message: String, onSuccess: (() -> Void)? = nil) {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isSendingInteractiveReply else {
            return
        }

        isSendingInteractiveReply = true
        interactiveReplyError = nil

        Task {
            let didSend = await sessionMonitor.submitInteractiveResponse(
                sessionId: session.sessionId,
                message: trimmed
            )

            await MainActor.run {
                isSendingInteractiveReply = false
                if didSend {
                    onSuccess?()
                } else {
                    interactiveReplyError = "Failed to send your response back to Claude."
                }
            }
        }
    }

    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isSendingMessage else { return }

        let originalInput = inputText
        isSendingMessage = true
        messageSendError = nil

        Task {
            let didSend = await sendToSession(text)

            await MainActor.run {
                isSendingMessage = false

                if didSend {
                    inputText = ""
                    resumeAutoscroll()
                    shouldScrollToBottom = true
                } else {
                    messageSendError = "Failed to send message to this Claude session."
                    if inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        inputText = originalInput
                    }
                }
            }
        }
    }

    private func sendToSession(_ text: String) async -> Bool {
        await MonitoredSessionMessageSender.shared.sendMessage(text, to: session)
    }

    private func interruptSession() {
        Task {
            await sessionMonitor.interruptSession(sessionId: sessionId)
        }
    }
}

// Moved to MessageItemView.swift

// Moved to UserMessageView.swift

// Moved to AssistantMessageView.swift

// Moved to ProcessingIndicatorView.swift


// Moved to SubagentViews.swift

// Moved to ThinkingView.swift

// Moved to InterruptedMessageView.swift




// Moved to ChatApprovalBar.swift

// Moved to NewMessagesIndicator.swift
