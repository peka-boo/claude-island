//
//  ChatContentView.swift
//  ClaudeIsland
//
//  Screenshot-inspired open chat workspace.
//

import SwiftUI

struct ChatContentView: View {
    @Bindable var viewModel: ChatViewModel
    let threadId: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var sessionMonitor = ClaudeSessionMonitor.shared

    @State private var hasAppeared = false
    @State private var isRenaming = false
    @State private var renameDraft = ""
    @State private var interactiveReplyDraft = ""
    @State private var isSendingInteractiveReply = false
    @State private var hasAppliedInitialTranscriptPosition = false
    @State private var lastStreamingAutoScrollAt: Date?

    private var canTerminate: Bool {
        viewModel.isStreaming || viewModel.isProcessing || viewModel.threadInfo?.status == .active
    }

    private var currentMonitoredSession: SessionState? {
        guard let sessionId = normalizeCLISessionId(viewModel.threadInfo?.cliSessionId) else {
            return nil
        }

        return sessionMonitor.instances.first {
            normalizeCLISessionId($0.sessionId) == sessionId
        }
    }

    private var currentPermission: PermissionContext? {
        currentMonitoredSession?.activePermission
    }

    private var currentLocalPermission: LocalCLIPermissionRequest? {
        viewModel.localPendingPermission
    }

    private var isUsingLocalPermissionFallback: Bool {
        currentPermission == nil && currentLocalPermission != nil
    }

    private var currentPermissionToolName: String? {
        currentPermission?.toolName ?? currentLocalPermission?.toolName
    }

    private var currentPermissionId: String? {
        currentPermission?.toolUseId ?? currentLocalPermission?.toolUseId
    }

    private var currentPermissionFormattedInput: String? {
        currentPermission?.formattedInput ?? currentLocalPermission?.formattedInput
    }

    private var isShowingInteractivePrompt: Bool {
        currentPermissionToolName == "AskUserQuestion"
    }

    private var isShowingPlanApproval: Bool {
        currentPermissionToolName == "ExitPlanMode"
    }

    private var currentPermissionRawInput: [String: Any]? {
        if let currentPermission {
            return currentPermission.toolInput?.mapValues(\.value)
        }

        if let inputJSON = currentLocalPermission?.toolInputJSON {
            return CLIPermissionFallbackTracker.parseToolInputJSONObject(inputJSON)
        }

        return nil
    }

    private var currentAskUserQuestionPrompt: AskUserQuestionPrompt? {
        guard let currentPermissionRawInput else { return nil }
        return AskUserQuestionPromptParser.parse(currentPermissionRawInput)
    }

    private var firstVisibleTranscriptItemId: String? {
        if viewModel.isUsingStructuredHistory {
            return viewModel.displayedStructuredItems.first?.id
        }

        return viewModel.messages.first?.id
    }

    private var hasVisibleTranscriptContent: Bool {
        let hasTranscriptItems = viewModel.isUsingStructuredHistory
            ? !viewModel.displayedStructuredItems.isEmpty
            : !viewModel.messages.isEmpty
        return hasTranscriptItems || viewModel.isStreaming || viewModel.error != nil
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                chatHeader
                    .frame(maxWidth: MainWindowTheme.conversationColumnMaxWidth, alignment: .leading)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 26)
                    .padding(.top, 22)
                    .padding(.bottom, 10)
                    .revealTransition(show: hasAppeared, y: -8)

                messageList
                    .padding(.horizontal, 18)
                    .padding(.top, 4)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                MessageInputView(
                    text: $viewModel.inputText,
                    commands: viewModel.availableCommands,
                    isProcessing: viewModel.isProcessing,
                    processingDescriptor: ComposerProcessingSupport.descriptor(
                        isProcessing: viewModel.isProcessing,
                        streamingText: viewModel.currentStreamingText,
                        thinkingText: viewModel.currentThinkingText
                    ),
                    canTerminate: canTerminate,
                    onSend: { Task { await viewModel.sendMessage() } },
                    onInterrupt: { Task { await viewModel.interrupt() } },
                    onTerminate: { Task { await viewModel.terminate() } }
                )
                .frame(maxWidth: MainWindowTheme.conversationColumnMaxWidth)
                .padding(.horizontal, 22)
                .padding(.bottom, 18)
                .padding(.top, 12)
                .revealTransition(show: hasAppeared, y: 8)
            }

                if let currentPermissionId, let currentPermissionToolName {
                if let prompt = currentAskUserQuestionPrompt, isShowingInteractivePrompt {
                    MainWindowStructuredAskPromptCard(
                        prompt: prompt,
                        isSending: isSendingInteractiveReply,
                        onSubmit: submitStructuredPromptResponse
                    )
                        .id(currentPermissionId)
                        .padding(.horizontal, 26)
                        .padding(.bottom, MainWindowTheme.scaled(126))
                        .frame(maxWidth: MainWindowTheme.conversationColumnMaxWidth)
                        .transition(MainWindowTheme.floatingCardTransition)
                        .zIndex(2)
                } else if isShowingInteractivePrompt {
                    MainWindowInteractivePromptCard(
                        toolInput: currentPermissionFormattedInput,
                        replyText: $interactiveReplyDraft,
                        isSending: isSendingInteractiveReply,
                        onSubmit: submitInteractivePromptResponse
                    )
                        .id(currentPermissionId)
                        .padding(.horizontal, 26)
                        .padding(.bottom, MainWindowTheme.scaled(126))
                        .frame(maxWidth: MainWindowTheme.conversationColumnMaxWidth)
                        .transition(MainWindowTheme.floatingCardTransition)
                        .zIndex(2)
                } else if isShowingPlanApproval {
                    MainWindowPlanApprovalCard(
                        toolInput: currentPermissionFormattedInput,
                        onApprove: approveCurrentPermission,
                        onDeny: { denyCurrentPermission(reason: nil) },
                        onDenyWithMessage: { message in
                            denyCurrentPermission(reason: message)
                        }
                    )
                        .id(currentPermissionId)
                        .padding(.horizontal, 26)
                        .padding(.bottom, MainWindowTheme.scaled(126))
                        .frame(maxWidth: MainWindowTheme.conversationColumnMaxWidth)
                        .transition(MainWindowTheme.floatingCardTransition)
                        .zIndex(2)
                } else {
                    MainWindowPermissionCard(
                        toolName: currentPermissionToolName,
                        toolInput: currentPermissionFormattedInput,
                        helperText: isUsingLocalPermissionFallback
                            ? "Claude CLI 没有抛出实时批准事件。允许后会自动重试这一轮。"
                            : nil,
                        denyLabel: isUsingLocalPermissionFallback ? "Dismiss" : "Deny",
                        approveLabel: isUsingLocalPermissionFallback ? "Allow & Retry" : "Allow Once",
                        onApprove: approveCurrentPermission,
                        onDeny: { denyCurrentPermission(reason: nil) }
                    )
                    .id(currentPermissionId)
                    .padding(.horizontal, 26)
                    .padding(.bottom, MainWindowTheme.scaled(126))
                    .frame(maxWidth: MainWindowTheme.conversationColumnMaxWidth)
                    .transition(MainWindowTheme.floatingCardTransition)
                    .zIndex(2)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(MainWindowTheme.workspace)
        .preferredColorScheme(.dark)
        .animation(MainWindowTheme.panelOpenAnimation, value: currentPermissionId ?? "")
        .task(id: threadId) {
            hasAppliedInitialTranscriptPosition = false
            lastStreamingAutoScrollAt = nil
            await viewModel.loadThread(threadId)
            renameDraft = viewModel.threadInfo?.title ?? "New Chat"
            isRenaming = false
            withAnimation(MainWindowTheme.panelOpenAnimation) {
                hasAppeared = true
            }
        }
        .onChange(of: viewModel.threadInfo?.title) { _, newTitle in
            if !isRenaming {
                renameDraft = newTitle ?? "New Chat"
            }
        }
        .onChange(of: currentPermissionId) { _, _ in
            interactiveReplyDraft = ""
            isSendingInteractiveReply = false
        }
    }

    private var chatHeader: some View {
        VStack(alignment: .leading, spacing: MainWindowTheme.scaled(14)) {
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 10) {
                        if isRenaming {
                            TextField("Session title", text: $renameDraft)
                                .textFieldStyle(.plain)
                                .font(.system(size: MainWindowTheme.scaled(24), weight: .medium))
                                .foregroundStyle(MainWindowTheme.textPrimary)
                                .frame(width: MainWindowTheme.scaled(320))
                                .onSubmit(commitRename)
                        } else {
                            Text(viewModel.threadInfo?.title ?? "New Chat")
                                .font(.system(size: MainWindowTheme.scaled(24), weight: .medium))
                                .foregroundStyle(MainWindowTheme.textPrimary)
                                .lineLimit(1)
                        }

                        Button(action: {
                            if isRenaming {
                                commitRename()
                            } else {
                                renameDraft = viewModel.threadInfo?.title ?? "New Chat"
                                isRenaming = true
                            }
                        }) {
                            Image(systemName: isRenaming ? "checkmark.circle.fill" : "square.and.pencil")
                                .font(.system(size: MainWindowTheme.scaled(13), weight: .medium))
                                .foregroundStyle(isRenaming ? TerminalColors.green : MainWindowTheme.textMuted)
                        }
                        .buttonStyle(.plain)
                    }

                    Text(canTerminate ? "Claude is live in this workspace" : "Ready for the next turn")
                        .font(.system(size: MainWindowTheme.scaled(13), weight: .medium))
                        .foregroundStyle(MainWindowTheme.textSecondary)
                }

                Spacer()
            }

            HStack(spacing: MainWindowTheme.scaled(10)) {
                headerChip(
                    icon: "folder",
                    title: viewModel.threadInfo?.projectName ?? "Workspace",
                    tint: MainWindowTheme.textSecondary
                )

                if let branch = viewModel.threadInfo?.gitBranch {
                    headerChip(
                        icon: "arrow.triangle.branch",
                        title: branch,
                        tint: MainWindowTheme.textSecondary
                    )
                }

                headerChip(
                    icon: canTerminate ? "waveform" : "checkmark.circle",
                    title: canTerminate ? "Live session" : "Ready",
                    tint: canTerminate ? TerminalColors.green : MainWindowTheme.textSecondary
                )
            }
        }
        .padding(.horizontal, MainWindowTheme.scaled(18))
        .padding(.vertical, MainWindowTheme.scaled(16))
        .mainWindowCard(
            fill: MainWindowTheme.panelElevated,
            border: MainWindowTheme.borderStrong,
            radius: MainWindowTheme.scaled(24),
            shadowOpacity: 0.12
        )
    }

    private func headerChip(icon: String, title: String, tint: Color) -> some View {
        HStack(spacing: MainWindowTheme.scaled(7)) {
            Image(systemName: icon)
                .font(.system(size: MainWindowTheme.scaled(11), weight: .semibold))
            Text(title)
                .lineLimit(1)
        }
        .font(.system(size: MainWindowTheme.scaled(12), weight: .medium))
        .foregroundStyle(tint)
        .padding(.horizontal, MainWindowTheme.scaled(12))
        .padding(.vertical, MainWindowTheme.scaled(8))
        .background(
            Capsule(style: .continuous)
                .fill(MainWindowTheme.panel)
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(MainWindowTheme.border, lineWidth: 1)
                )
        )
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 28) {
                    if viewModel.hasOlderTranscriptItems || viewModel.isLoadingOlderMessages {
                        transcriptPaginationHeader(with: proxy)
                            .padding(.top, MainWindowTheme.scaled(6))
                            .transition(MainWindowTheme.sectionRevealTransition)
                    }

                    if viewModel.isUsingStructuredHistory {
                        ForEach(viewModel.displayedStructuredItems) { item in
                            MessageItemView(
                                item: item,
                                sessionId: viewModel.threadInfo?.cliSessionId ?? threadId,
                                agentDescriptions: viewModel.structuredHistory.agentDescriptions
                            )
                            .id(item.id)
                            .transition(MainWindowTheme.adaptiveTransition(.opacity.combined(with: .move(edge: .bottom)), reduceMotion: reduceMotion))
                        }
                    } else {
                        ForEach(viewModel.messages) { message in
                            MessageBubbleView(message: message)
                                .id(message.id)
                                .transition(MainWindowTheme.adaptiveTransition(.opacity.combined(with: .move(edge: .bottom)), reduceMotion: reduceMotion))
                        }
                    }

                    if viewModel.isStreaming {
                        streamingBubble
                            .id("streaming")
                            .transition(MainWindowTheme.adaptiveTransition(.opacity.combined(with: .move(edge: .bottom)), reduceMotion: reduceMotion))
                    }

                    if let error = viewModel.error {
                        errorBubble(error)
                            .id("error")
                            .transition(MainWindowTheme.adaptiveTransition(.opacity.combined(with: .move(edge: .bottom)), reduceMotion: reduceMotion))
                    }

                    if let bottomAnchor = ChatTranscriptScrollSupport.bottomScrollTarget(
                        hasVisibleContent: hasVisibleTranscriptContent
                    ) {
                        Color.clear
                            .frame(height: 1)
                            .id(bottomAnchor)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, MainWindowTheme.scaled(18))
                .padding(.top, MainWindowTheme.scaled(6))
                .padding(.bottom, MainWindowTheme.scaled(40))
                .animation(
                    MainWindowTheme.adaptiveAnimation(MainWindowTheme.contentSwapAnimation, reduceMotion: reduceMotion),
                    value: viewModel.messages.last?.id ?? ""
                )
                .animation(
                    MainWindowTheme.adaptiveAnimation(MainWindowTheme.contentSwapAnimation, reduceMotion: reduceMotion),
                    value: viewModel.displayedStructuredItems.last?.id ?? ""
                )
                .animation(
                    MainWindowTheme.adaptiveAnimation(MainWindowTheme.softFadeAnimation, reduceMotion: reduceMotion),
                    value: viewModel.isStreaming
                )
            }
            .frame(maxWidth: MainWindowTheme.conversationColumnMaxWidth)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .textSelection(.enabled)
            .scrollIndicators(.never)
            .onChange(of: viewModel.messages) { oldMessages, newMessages in
                switch ChatTranscriptScrollSupport.scrollAction(
                    oldItems: oldMessages,
                    newItems: newMessages,
                    hasAppliedInitialPosition: hasAppliedInitialTranscriptPosition
                ) {
                case .none:
                    break
                case .jumpToLatest:
                    var transaction = Transaction()
                    transaction.animation = nil
                    withTransaction(transaction) {
                        scrollToBottom(with: proxy)
                    }
                case .animateToLatest:
                    withOptionalAnimation(MainWindowTheme.hoverAnimation) {
                        scrollToBottom(with: proxy)
                    }
                }
            }
            .onChange(of: viewModel.displayedStructuredItems) { oldItems, newItems in
                switch ChatTranscriptScrollSupport.scrollAction(
                    oldItems: oldItems,
                    newItems: newItems,
                    hasAppliedInitialPosition: hasAppliedInitialTranscriptPosition
                ) {
                case .none:
                    break
                case .jumpToLatest:
                    var transaction = Transaction()
                    transaction.animation = nil
                    withTransaction(transaction) {
                        scrollToBottom(with: proxy)
                    }
                case .animateToLatest:
                    withOptionalAnimation(MainWindowTheme.contentSwapAnimation) {
                        scrollToBottom(with: proxy)
                    }
                }
            }
            .onChange(of: viewModel.currentStreamingText) { _, _ in
                guard !viewModel.currentStreamingText.isEmpty,
                      hasAppliedInitialTranscriptPosition else { return }

                let now = Date()
                let elapsedSinceLastAutoScroll = lastStreamingAutoScrollAt.map {
                    now.timeIntervalSince($0)
                }

                switch ChatTranscriptScrollSupport.streamingScrollAction(
                    hasAppliedInitialPosition: hasAppliedInitialTranscriptPosition,
                    elapsedSinceLastAutoScroll: elapsedSinceLastAutoScroll
                ) {
                case .none:
                    break
                case .jumpToLatest:
                    lastStreamingAutoScrollAt = now
                    var transaction = Transaction()
                    transaction.animation = nil
                    withTransaction(transaction) {
                        scrollToBottom(with: proxy)
                    }
                case .animateToLatest:
                    lastStreamingAutoScrollAt = now
                    withOptionalAnimation(MainWindowTheme.softFadeAnimation) {
                        scrollToBottom(with: proxy)
                    }
                }
            }
        }
    }

    private func transcriptPaginationHeader(with proxy: ScrollViewProxy) -> some View {
        HStack(spacing: 10) {
            if viewModel.isLoadingOlderMessages {
                ProgressView()
                    .controlSize(.small)
                    .transition(.opacity)
            }

            Text(viewModel.isLoadingOlderMessages ? "Loading earlier messages..." : "Scroll up to load earlier messages")
                .font(.system(size: MainWindowTheme.scaled(11), weight: .medium))
                .foregroundStyle(MainWindowTheme.textMuted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, MainWindowTheme.scaled(10))
        .onAppear {
            loadOlderContentIfNeeded(with: proxy)
        }
    }

    private func scrollToBottom(with proxy: ScrollViewProxy) {
        guard let bottomAnchor = ChatTranscriptScrollSupport.bottomScrollTarget(
            hasVisibleContent: hasVisibleTranscriptContent
        ) else {
            return
        }

        hasAppliedInitialTranscriptPosition = true
        proxy.scrollTo(bottomAnchor, anchor: .bottom)
    }

    private func withOptionalAnimation(_ animation: Animation, _ updates: () -> Void) {
        if reduceMotion {
            updates()
        } else {
            withAnimation(animation) {
                updates()
            }
        }
    }

    private func loadOlderContentIfNeeded(with proxy: ScrollViewProxy) {
        guard hasAppliedInitialTranscriptPosition,
              viewModel.hasOlderTranscriptItems,
              !viewModel.isLoadingOlderMessages else {
            return
        }

        let anchorId = firstVisibleTranscriptItemId
        Task {
            await viewModel.loadOlderMessages()

            guard let anchorId else { return }

            await MainActor.run {
                var transaction = Transaction()
                transaction.animation = nil
                withTransaction(transaction) {
                    proxy.scrollTo(anchorId, anchor: .top)
                }
            }
        }
    }

    private func commitRename() {
        let trimmed = renameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            isRenaming = false
            renameDraft = viewModel.threadInfo?.title ?? "New Chat"
            return
        }

        isRenaming = false
        Task {
            await viewModel.renameCurrentThread(to: trimmed)
        }
    }

    private func approveCurrentPermission() {
        if let sessionId = currentMonitoredSession?.sessionId,
           currentPermission != nil {
            sessionMonitor.approvePermission(sessionId: sessionId)
            return
        }

        Task {
            await viewModel.approveLocalPermissionFallback()
        }
    }

    private func denyCurrentPermission(reason: String?) {
        if let sessionId = currentMonitoredSession?.sessionId,
           currentPermission != nil {
            let trimmedReason = reason?.trimmingCharacters(in: .whitespacesAndNewlines)
            sessionMonitor.denyPermission(sessionId: sessionId, reason: trimmedReason?.isEmpty == false ? trimmedReason : nil)
            return
        }

        Task {
            await viewModel.denyLocalPermissionFallback()
        }
    }

    private func submitInteractivePromptResponse() {
        let trimmed = interactiveReplyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return
        }

        sendInteractiveResponse(trimmed) {
            interactiveReplyDraft = ""
        }
    }

    private func submitStructuredPromptResponse(_ submission: AskUserQuestionSubmission) {
        sendInteractiveResponse(submission.responseText)
    }

    private func sendInteractiveResponse(_ message: String, onSuccess: (() -> Void)? = nil) {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              !isSendingInteractiveReply else {
            return
        }

        isSendingInteractiveReply = true
        viewModel.error = nil

        Task {
            let didSend: Bool
            if let sessionId = currentMonitoredSession?.sessionId,
               currentPermission != nil {
                didSend = await sessionMonitor.submitInteractiveResponse(
                    sessionId: sessionId,
                    message: trimmed
                )
            } else if currentLocalPermission?.toolName == "AskUserQuestion" {
                didSend = await viewModel.submitLocalInteractivePromptResponse(trimmed)
            } else {
                didSend = false
            }

            await MainActor.run {
                isSendingInteractiveReply = false
                if didSend {
                    onSuccess?()
                } else {
                    viewModel.error = "Failed to send your response back to Claude."
                }
            }
        }
    }

    private var streamingBubble: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !viewModel.currentThinkingText.isEmpty {
                DisclosureGroup {
                    liveStreamingText(
                        viewModel.currentThinkingText,
                        color: MainWindowTheme.textSecondary,
                        fontSize: 12
                    )
                        .padding(.top, 8)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "brain")
                            .font(.system(size: 10, weight: .medium))
                        Text("Reasoning")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundStyle(TerminalColors.magenta)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.white.opacity(0.04))
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                        )
                )
            }

            if !viewModel.currentStreamingText.isEmpty {
                liveStreamingText(
                    viewModel.currentStreamingText,
                    color: MainWindowTheme.textPrimary,
                    fontSize: 15
                )
            }

            MainWindowStreamingStatusRow()
        }
        .padding(.horizontal, 2)
    }

    @ViewBuilder
    private func liveStreamingText(_ text: String, color: Color, fontSize: CGFloat) -> some View {
        switch StreamingResponseRenderingSupport.mode(isStreaming: viewModel.isStreaming) {
        case .plainText:
            Text(verbatim: text)
                .font(.system(size: fontSize))
                .foregroundStyle(color)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        case .markdown:
            MarkdownText(text, color: color, fontSize: fontSize)
        }
    }

    private func errorBubble(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(TerminalColors.red)
            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(MainWindowTheme.textPrimary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(TerminalColors.red.opacity(0.10))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(TerminalColors.red.opacity(0.20), lineWidth: 1)
                )
        )
    }
}

private struct MainWindowPermissionCard: View {
    let toolName: String
    let toolInput: String?
    let helperText: String?
    let denyLabel: String
    let approveLabel: String
    let onApprove: () -> Void
    let onDeny: () -> Void

    @State private var isHovered = false
    @State private var showActions = false

    var body: some View {
        HStack(alignment: .center, spacing: MainWindowTheme.scaled(16)) {
            VStack(alignment: .leading, spacing: MainWindowTheme.scaled(8)) {
                HStack(spacing: MainWindowTheme.scaled(10)) {
                    Image(systemName: "checkmark.shield")
                        .font(.system(size: MainWindowTheme.scaled(14), weight: .semibold))
                        .foregroundStyle(TerminalColors.amber)

                    Text("Permission Request")
                        .font(.system(size: MainWindowTheme.scaled(13), weight: .semibold))
                        .foregroundStyle(MainWindowTheme.textPrimary)

                    Text(MCPToolFormatter.formatToolName(toolName))
                        .font(.system(size: MainWindowTheme.scaled(12), weight: .medium, design: .monospaced))
                        .foregroundStyle(TerminalColors.amber)
                }

                Text(toolInput ?? "Claude needs approval before this tool can continue.")
                    .font(.system(size: MainWindowTheme.scaled(12)))
                    .foregroundStyle(MainWindowTheme.textSecondary)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)

                if let helperText, !helperText.isEmpty {
                    Text(helperText)
                        .font(.system(size: MainWindowTheme.scaled(11), weight: .medium))
                        .foregroundStyle(TerminalColors.amber.opacity(0.88))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
            }

            Spacer(minLength: MainWindowTheme.scaled(12))

            HStack(spacing: MainWindowTheme.scaled(10)) {
                MainWindowCardActionButton(
                    title: denyLabel,
                    style: .secondary,
                    action: onDeny
                )
                .opacity(showActions ? 1 : 0)
                .offset(y: showActions ? 0 : 8)

                MainWindowCardActionButton(
                    title: approveLabel,
                    style: .primary,
                    action: onApprove
                )
                .opacity(showActions ? 1 : 0)
                .offset(y: showActions ? 0 : 10)
            }
        }
        .padding(.horizontal, MainWindowTheme.scaled(18))
        .padding(.vertical, MainWindowTheme.scaled(16))
        .background(
            RoundedRectangle(cornerRadius: MainWindowTheme.scaled(22), style: .continuous)
                .fill(Color(red: 0.09, green: 0.08, blue: 0.07).opacity(isHovered ? 0.98 : 0.94))
                .overlay(
                    RoundedRectangle(cornerRadius: MainWindowTheme.scaled(22), style: .continuous)
                        .strokeBorder(TerminalColors.amber.opacity(0.28), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.28), radius: 30, x: 0, y: 18)
        )
        .onHover { hovering in
            withAnimation(MainWindowTheme.hoverAnimation) {
                isHovered = hovering
            }
        }
        .task {
            withAnimation(MainWindowTheme.contentSwapAnimation.delay(0.04)) {
                showActions = true
            }
        }
    }
}

private struct MainWindowPlanApprovalCard: View {
    let toolInput: String?
    let onApprove: () -> Void
    let onDeny: () -> Void
    let onDenyWithMessage: (String) -> Void

    @State private var feedbackDraft = ""
    @State private var showActions = false

    var body: some View {
        VStack(alignment: .leading, spacing: MainWindowTheme.scaled(14)) {
            VStack(alignment: .leading, spacing: MainWindowTheme.scaled(8)) {
                HStack(spacing: MainWindowTheme.scaled(10)) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: MainWindowTheme.scaled(14), weight: .semibold))
                        .foregroundStyle(TerminalColors.amber)

                    Text("Plan Approval")
                        .font(.system(size: MainWindowTheme.scaled(13), weight: .semibold))
                        .foregroundStyle(MainWindowTheme.textPrimary)
                }

                Text(toolInput ?? "Claude is asking to leave planning mode and start executing.")
                    .font(.system(size: MainWindowTheme.scaled(12)))
                    .foregroundStyle(MainWindowTheme.textSecondary)
                    .lineLimit(4)
                    .multilineTextAlignment(.leading)
            }

            HStack(spacing: MainWindowTheme.scaled(10)) {
                MainWindowCardActionButton(
                    title: "Reject",
                    style: .secondary,
                    action: onDeny
                )
                .opacity(showActions ? 1 : 0)
                .offset(y: showActions ? 0 : 8)

                MainWindowCardActionButton(
                    title: "Approve & Execute",
                    style: .primary,
                    action: onApprove
                )
                .opacity(showActions ? 1 : 0)
                .offset(y: showActions ? 0 : 10)
            }

            HStack(spacing: MainWindowTheme.scaled(10)) {
                TextField("Ask Claude to revise the plan...", text: $feedbackDraft)
                    .textFieldStyle(.plain)
                    .font(.system(size: MainWindowTheme.scaled(13)))
                    .foregroundStyle(MainWindowTheme.textPrimary)
                    .padding(.horizontal, MainWindowTheme.scaled(14))
                    .padding(.vertical, MainWindowTheme.scaled(11))
                    .background(
                        RoundedRectangle(cornerRadius: MainWindowTheme.scaled(16), style: .continuous)
                            .fill(Color.white.opacity(0.05))
                            .overlay(
                                RoundedRectangle(cornerRadius: MainWindowTheme.scaled(16), style: .continuous)
                                    .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
                            )
                    )
                    .onSubmit(submitFeedback)

                MainWindowCardActionButton(
                    title: "Do This Instead",
                    style: .accent,
                    isEnabled: !feedbackDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                    action: submitFeedback
                )
                .disabled(feedbackDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(.horizontal, MainWindowTheme.scaled(18))
        .padding(.vertical, MainWindowTheme.scaled(16))
        .background(
            RoundedRectangle(cornerRadius: MainWindowTheme.scaled(22), style: .continuous)
                .fill(Color(red: 0.09, green: 0.08, blue: 0.07).opacity(0.94))
                .overlay(
                    RoundedRectangle(cornerRadius: MainWindowTheme.scaled(22), style: .continuous)
                        .strokeBorder(TerminalColors.amber.opacity(0.24), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.24), radius: 28, x: 0, y: 16)
        )
        .task {
            withAnimation(MainWindowTheme.contentSwapAnimation.delay(0.04)) {
                showActions = true
            }
        }
    }

    private func submitFeedback() {
        let trimmed = feedbackDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        onDenyWithMessage(trimmed)
    }
}

private struct MainWindowInteractivePromptCard: View {
    let toolInput: String?
    @Binding var replyText: String
    let isSending: Bool
    let onSubmit: () -> Void

    @State private var showAction = false

    var body: some View {
        VStack(alignment: .leading, spacing: MainWindowTheme.scaled(14)) {
            VStack(alignment: .leading, spacing: MainWindowTheme.scaled(8)) {
                HStack(spacing: MainWindowTheme.scaled(10)) {
                    Image(systemName: "bubble.left.and.exclamationmark.bubble.right")
                        .font(.system(size: MainWindowTheme.scaled(14), weight: .semibold))
                        .foregroundStyle(TerminalColors.amber)

                    Text("Claude Needs Input")
                        .font(.system(size: MainWindowTheme.scaled(13), weight: .semibold))
                        .foregroundStyle(MainWindowTheme.textPrimary)
                }

                Text(toolInput ?? "This turn is waiting for an interactive answer before it can continue.")
                    .font(.system(size: MainWindowTheme.scaled(12)))
                    .foregroundStyle(MainWindowTheme.textSecondary)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
            }

            HStack(spacing: MainWindowTheme.scaled(12)) {
                TextField("Reply to Claude...", text: $replyText)
                    .textFieldStyle(.plain)
                    .font(.system(size: MainWindowTheme.scaled(13)))
                    .foregroundStyle(MainWindowTheme.textPrimary)
                    .padding(.horizontal, MainWindowTheme.scaled(14))
                    .padding(.vertical, MainWindowTheme.scaled(11))
                    .background(
                        RoundedRectangle(cornerRadius: MainWindowTheme.scaled(16), style: .continuous)
                            .fill(Color.white.opacity(0.05))
                            .overlay(
                                RoundedRectangle(cornerRadius: MainWindowTheme.scaled(16), style: .continuous)
                                    .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
                            )
                    )
                    .onSubmit(onSubmit)

                MainWindowIconActionButton(
                    systemImage: "arrow.up",
                    isEnabled: !replyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSending,
                    isLoading: isSending,
                    action: onSubmit
                )
                .opacity(showAction ? 1 : 0)
                .offset(y: showAction ? 0 : 10)
                .disabled(replyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSending)
            }
        }
        .padding(.horizontal, MainWindowTheme.scaled(18))
        .padding(.vertical, MainWindowTheme.scaled(16))
        .background(
            RoundedRectangle(cornerRadius: MainWindowTheme.scaled(22), style: .continuous)
                .fill(Color(red: 0.09, green: 0.08, blue: 0.07).opacity(0.94))
                .overlay(
                    RoundedRectangle(cornerRadius: MainWindowTheme.scaled(22), style: .continuous)
                        .strokeBorder(TerminalColors.amber.opacity(0.22), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.24), radius: 28, x: 0, y: 16)
        )
        .task {
            withAnimation(MainWindowTheme.contentSwapAnimation.delay(0.05)) {
                showAction = true
            }
        }
    }
}

private struct MainWindowStructuredAskPromptCard: View {
    let prompt: AskUserQuestionPrompt
    let isSending: Bool
    let onSubmit: (AskUserQuestionSubmission) -> Void

    @State private var currentStepIndex = 0
    @State private var selectedOptions: [String: [String]] = [:]
    @State private var customAnswers: [String: String] = [:]
    @State private var notes: [String: String] = [:]
    @State private var customEnabled: [String: Bool] = [:]
    @State private var hoveredOptionID: String?

    private var draftAnswers: [String: AskUserQuestionDraftAnswer] {
        Dictionary(uniqueKeysWithValues: prompt.questions.map { question in
            (
                question.question,
                AskUserQuestionDraftAnswer(
                    selectedOptionLabels: selectedOptions[question.question] ?? [],
                    customAnswer: customEnabled[question.question] == true ? customAnswers[question.question] : nil,
                    notes: notes[question.question]
                )
            )
        })
    }

    private var wizardSteps: [AskUserQuestionWizardStep] {
        AskUserQuestionWizardSupport.steps(prompt: prompt, drafts: draftAnswers)
    }

    private var clampedStepIndex: Int {
        min(max(currentStepIndex, 0), max(prompt.questions.count, 0))
    }

    private var currentQuestion: AskUserQuestionPromptItem? {
        guard clampedStepIndex < prompt.questions.count else { return nil }
        return prompt.questions[clampedStepIndex]
    }

    private var canAdvanceCurrentStep: Bool {
        guard let currentQuestion else {
            return submission != nil
        }
        return AskUserQuestionWizardSupport.canAdvance(
            question: currentQuestion,
            draft: draftAnswers[currentQuestion.question]
        )
    }

    private var submission: AskUserQuestionSubmission? {
        AskUserQuestionSubmissionBuilder.build(prompt: prompt, drafts: draftAnswers)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: MainWindowTheme.scaled(16)) {
            wizardHeader

            Group {
                if let currentQuestion {
                    ScrollView {
                        questionSection(currentQuestion, stepIndex: clampedStepIndex)
                            .padding(.vertical, MainWindowTheme.scaled(2))
                    }
                    .frame(maxHeight: MainWindowTheme.scaled(360))
                    .scrollIndicators(.never)
                } else {
                    ScrollView {
                        submitReviewSection
                            .padding(.vertical, MainWindowTheme.scaled(2))
                    }
                    .frame(maxHeight: MainWindowTheme.scaled(360))
                    .scrollIndicators(.never)
                }
            }

            footerActions
        }
        .frame(maxWidth: MainWindowTheme.scaled(780), alignment: .leading)
        .padding(.horizontal, MainWindowTheme.scaled(18))
        .padding(.vertical, MainWindowTheme.scaled(16))
        .background(
            RoundedRectangle(cornerRadius: MainWindowTheme.scaled(22), style: .continuous)
                .fill(Color(red: 0.09, green: 0.08, blue: 0.07).opacity(0.96))
                .overlay(
                    RoundedRectangle(cornerRadius: MainWindowTheme.scaled(22), style: .continuous)
                        .strokeBorder(TerminalColors.amber.opacity(0.24), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.26), radius: 30, x: 0, y: 16)
        )
        .onAppear {
            currentStepIndex = AskUserQuestionWizardSupport.initialStepIndex(
                prompt: prompt,
                drafts: draftAnswers
            )
        }
    }

    private var wizardHeader: some View {
        HStack(spacing: MainWindowTheme.scaled(10)) {
            Button(action: moveToPreviousStep) {
                Image(systemName: "arrow.left")
                    .font(.system(size: MainWindowTheme.scaled(13), weight: .semibold))
                    .foregroundStyle(clampedStepIndex == 0 ? MainWindowTheme.textMuted : MainWindowTheme.textPrimary)
                    .frame(width: MainWindowTheme.scaled(34), height: MainWindowTheme.scaled(34))
                    .background(
                        Circle()
                            .fill(Color.white.opacity(clampedStepIndex == 0 ? 0.05 : 0.08))
                    )
            }
            .buttonStyle(.plain)
            .disabled(clampedStepIndex == 0)

            ScrollView(.horizontal) {
                HStack(spacing: MainWindowTheme.scaled(8)) {
                    ForEach(wizardSteps) { step in
                        MainWindowWizardStepChip(
                            title: step.title,
                            index: step.index,
                            isCurrent: step.index == clampedStepIndex,
                            isComplete: step.isComplete,
                            isSubmitStep: {
                                if case .submit = step.kind { return true }
                                return false
                            }(),
                            action: { moveToStep(step.index) }
                        )
                    }
                }
                .padding(.vertical, MainWindowTheme.scaled(2))
            }
            .scrollIndicators(.never)
        }
    }

    private var submitReviewSection: some View {
        VStack(alignment: .leading, spacing: MainWindowTheme.scaled(14)) {
            HStack(spacing: MainWindowTheme.scaled(10)) {
                Image(systemName: "checklist")
                    .font(.system(size: MainWindowTheme.scaled(14), weight: .semibold))
                    .foregroundStyle(TerminalColors.green)

                Text("Review & Submit")
                    .font(.system(size: MainWindowTheme.scaled(15), weight: .semibold))
                    .foregroundStyle(MainWindowTheme.textPrimary)
            }

            Text("Claude is waiting for your final answer. Review the collected selections below before sending them back.")
                .font(.system(size: MainWindowTheme.scaled(12)))
                .foregroundStyle(MainWindowTheme.textSecondary)

            VStack(alignment: .leading, spacing: MainWindowTheme.scaled(10)) {
                ForEach(Array(prompt.questions.enumerated()), id: \.element.id) { index, question in
                    let answerText = AskUserQuestionWizardSupport.answerText(
                        question: question,
                        draft: draftAnswers[question.question]
                    )
                    let noteText = notes[question.question]?.trimmingCharacters(in: .whitespacesAndNewlines)

                    Button(action: { moveToStep(index) }) {
                        VStack(alignment: .leading, spacing: MainWindowTheme.scaled(6)) {
                            HStack(spacing: MainWindowTheme.scaled(8)) {
                                Text(AskUserQuestionWizardSupport.stepTitle(for: question, index: index).uppercased())
                                    .font(.system(size: MainWindowTheme.scaled(10), weight: .semibold))
                                    .foregroundStyle(MainWindowTheme.textMuted)

                                Spacer()

                                Image(systemName: "arrow.up.left")
                                    .font(.system(size: MainWindowTheme.scaled(11), weight: .semibold))
                                    .foregroundStyle(MainWindowTheme.textMuted)
                            }

                            Text(question.question)
                                .font(.system(size: MainWindowTheme.scaled(13), weight: .medium))
                                .foregroundStyle(MainWindowTheme.textPrimary)
                                .multilineTextAlignment(.leading)

                            Text(answerText ?? "No answer yet.")
                                .font(.system(size: MainWindowTheme.scaled(12)))
                                .foregroundStyle(answerText == nil ? TerminalColors.amber : MainWindowTheme.textSecondary)
                                .multilineTextAlignment(.leading)

                            if let noteText, !noteText.isEmpty {
                                Text("Note: \(noteText)")
                                    .font(.system(size: MainWindowTheme.scaled(11)))
                                    .foregroundStyle(MainWindowTheme.textMuted)
                                    .multilineTextAlignment(.leading)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, MainWindowTheme.scaled(14))
                        .padding(.vertical, MainWindowTheme.scaled(14))
                        .background(
                            RoundedRectangle(cornerRadius: MainWindowTheme.scaled(18), style: .continuous)
                                .fill(Color.white.opacity(0.04))
                                .overlay(
                                    RoundedRectangle(cornerRadius: MainWindowTheme.scaled(18), style: .continuous)
                                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                                )
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var footerActions: some View {
        HStack(spacing: MainWindowTheme.scaled(10)) {
            Text(footerHint)
                .font(.system(size: MainWindowTheme.scaled(11)))
                .foregroundStyle(MainWindowTheme.textSecondary)

            Spacer()

            if clampedStepIndex > 0 {
                Button(action: moveToPreviousStep) {
                    Text("Back")
                        .font(.system(size: MainWindowTheme.scaled(13), weight: .medium))
                        .foregroundStyle(MainWindowTheme.textPrimary)
                        .padding(.horizontal, MainWindowTheme.scaled(16))
                        .padding(.vertical, MainWindowTheme.scaled(10))
                        .background(
                            Capsule()
                                .fill(Color.white.opacity(0.08))
                        )
                }
                .buttonStyle(.plain)
                .disabled(isSending)
            }

            Button(action: handlePrimaryAction) {
                if isSending && currentQuestion == nil {
                    ProgressView()
                        .controlSize(.small)
                        .tint(Color.black)
                        .frame(width: MainWindowTheme.scaled(132), height: MainWindowTheme.scaled(40))
                } else {
                    Text(primaryActionTitle)
                        .font(.system(size: MainWindowTheme.scaled(13), weight: .semibold))
                        .foregroundStyle(primaryActionEnabled ? Color.black : MainWindowTheme.textMuted)
                        .padding(.horizontal, MainWindowTheme.scaled(16))
                        .padding(.vertical, MainWindowTheme.scaled(10))
                }
            }
            .buttonStyle(.plain)
            .background(
                Capsule()
                    .fill(primaryActionEnabled ? Color.white.opacity(0.96) : Color.white.opacity(0.18))
            )
            .disabled(!primaryActionEnabled || isSending)
        }
    }

    private var footerHint: String {
        if let currentQuestion {
            return AskUserQuestionWizardSupport.canAdvance(
                question: currentQuestion,
                draft: draftAnswers[currentQuestion.question]
            )
                ? "This step is ready. Continue when you want."
                : "Choose an option, or type your own answer to continue."
        }

        return submission == nil
            ? "Answer the remaining questions before submitting."
            : "Everything looks good. Send this reply back to Claude."
    }

    private var primaryActionTitle: String {
        if currentQuestion == nil {
            return "Submit Answers"
        }
        return clampedStepIndex == prompt.questions.count - 1 ? "Review" : "Next"
    }

    private var primaryActionEnabled: Bool {
        guard currentQuestion != nil else {
            return submission != nil
        }
        return canAdvanceCurrentStep
    }

    @ViewBuilder
    private func questionSection(_ question: AskUserQuestionPromptItem, stepIndex: Int) -> some View {
        VStack(alignment: .leading, spacing: MainWindowTheme.scaled(12)) {
            HStack(alignment: .center, spacing: MainWindowTheme.scaled(10)) {
                Text(AskUserQuestionWizardSupport.stepTitle(for: question, index: stepIndex).uppercased())
                    .font(.system(size: MainWindowTheme.scaled(10), weight: .semibold))
                    .foregroundStyle(MainWindowTheme.textMuted)
                    .padding(.horizontal, MainWindowTheme.scaled(10))
                    .padding(.vertical, MainWindowTheme.scaled(6))
                    .background(
                        Capsule()
                            .fill(Color.white.opacity(0.06))
                    )

                Spacer()

                Text("(\(stepIndex + 1)/\(prompt.questions.count))")
                    .font(.system(size: MainWindowTheme.scaled(12), weight: .medium))
                    .foregroundStyle(MainWindowTheme.textSecondary)
            }

            HStack(alignment: .firstTextBaseline, spacing: MainWindowTheme.scaled(8)) {
                Text(question.question)
                    .font(.system(size: MainWindowTheme.scaled(18), weight: .semibold))
                    .foregroundStyle(MainWindowTheme.textPrimary)
                    .multilineTextAlignment(.leading)

                if question.multiSelect {
                    Text("Multi-select")
                        .font(.system(size: MainWindowTheme.scaled(10), weight: .semibold))
                        .foregroundStyle(TerminalColors.amber)
                        .padding(.horizontal, MainWindowTheme.scaled(8))
                        .padding(.vertical, MainWindowTheme.scaled(4))
                        .background(
                            Capsule()
                                .fill(TerminalColors.amber.opacity(0.14))
                        )
                }
            }

            Text(question.multiSelect
                 ? "Choose one or more options, or type your own answer."
                 : "Choose one option, or type your own answer.")
                .font(.system(size: MainWindowTheme.scaled(12)))
                .foregroundStyle(MainWindowTheme.textSecondary)

            VStack(alignment: .leading, spacing: MainWindowTheme.scaled(10)) {
                ForEach(Array(question.options.enumerated()), id: \.element.id) { offset, option in
                    MainWindowQuestionOptionButton(
                        leadingLabel: "\(offset + 1).",
                        title: option.displayLabel,
                        description: option.description,
                        isRecommended: option.isRecommended,
                        isSelected: selectedOptions[question.question]?.contains(option.rawLabel) == true,
                        isMultiSelect: question.multiSelect,
                        isHovered: hoveredOptionID == option.id,
                        action: { toggleOption(option, in: question) }
                    )
                    .onHover { isHovered in
                        withAnimation(MainWindowTheme.hoverAnimation) {
                            hoveredOptionID = isHovered ? option.id : nil
                        }
                    }
                }

                MainWindowQuestionOptionButton(
                    leadingLabel: "\(question.options.count + 1).",
                    title: "Type something.",
                    description: question.multiSelect ? "Append a custom answer to your selection" : "Answer with your own text",
                    isRecommended: false,
                    isSelected: customEnabled[question.question] == true,
                    isMultiSelect: question.multiSelect,
                    isHovered: hoveredOptionID == "\(question.question)-custom",
                    action: { toggleCustomAnswer(for: question) }
                )
                .onHover { isHovered in
                    withAnimation(MainWindowTheme.hoverAnimation) {
                        hoveredOptionID = isHovered ? "\(question.question)-custom" : nil
                    }
                }
            }

            if customEnabled[question.question] == true {
                TextField(
                    question.multiSelect ? "Type another answer..." : "Type your answer...",
                    text: binding(for: question.question, in: $customAnswers)
                )
                .textFieldStyle(.plain)
                .font(.system(size: MainWindowTheme.scaled(13)))
                .foregroundStyle(MainWindowTheme.textPrimary)
                .padding(.horizontal, MainWindowTheme.scaled(14))
                .padding(.vertical, MainWindowTheme.scaled(11))
                .background(
                    RoundedRectangle(cornerRadius: MainWindowTheme.scaled(16), style: .continuous)
                        .fill(Color.white.opacity(0.05))
                        .overlay(
                            RoundedRectangle(cornerRadius: MainWindowTheme.scaled(16), style: .continuous)
                                .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
                        )
                )
            }

            if shouldShowNotes(for: question) {
                TextField(
                    "Optional note for Claude...",
                    text: binding(for: question.question, in: $notes)
                )
                .textFieldStyle(.plain)
                .font(.system(size: MainWindowTheme.scaled(12)))
                .foregroundStyle(MainWindowTheme.textSecondary)
                .padding(.horizontal, MainWindowTheme.scaled(14))
                .padding(.vertical, MainWindowTheme.scaled(10))
                .background(
                    RoundedRectangle(cornerRadius: MainWindowTheme.scaled(16), style: .continuous)
                        .fill(Color.white.opacity(0.04))
                        .overlay(
                            RoundedRectangle(cornerRadius: MainWindowTheme.scaled(16), style: .continuous)
                                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                        )
                )
            }
        }
        .padding(.horizontal, MainWindowTheme.scaled(14))
        .padding(.vertical, MainWindowTheme.scaled(14))
        .background(
            RoundedRectangle(cornerRadius: MainWindowTheme.scaled(18), style: .continuous)
                .fill(Color.white.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: MainWindowTheme.scaled(18), style: .continuous)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
    }

    private func handlePrimaryAction() {
        if currentQuestion == nil {
            submitCurrentSelection()
        } else {
            moveToNextStep()
        }
    }

    private func moveToStep(_ index: Int) {
        withAnimation(MainWindowTheme.hoverAnimation) {
            currentStepIndex = min(max(index, 0), prompt.questions.count)
        }
    }

    private func moveToPreviousStep() {
        guard clampedStepIndex > 0 else { return }
        moveToStep(clampedStepIndex - 1)
    }

    private func moveToNextStep() {
        guard canAdvanceCurrentStep else { return }
        moveToStep(min(clampedStepIndex + 1, prompt.questions.count))
    }

    private func toggleOption(_ option: AskUserQuestionPromptOption, in question: AskUserQuestionPromptItem) {
        var current = selectedOptions[question.question] ?? []

        if question.multiSelect {
            if let existingIndex = current.firstIndex(of: option.rawLabel) {
                current.remove(at: existingIndex)
            } else {
                current.append(option.rawLabel)
            }
        } else {
            current = [option.rawLabel]
            customEnabled[question.question] = false
            customAnswers[question.question] = ""
        }

        selectedOptions[question.question] = current
    }

    private func toggleCustomAnswer(for question: AskUserQuestionPromptItem) {
        let key = question.question
        let nextValue = !(customEnabled[key] ?? false)
        customEnabled[key] = nextValue

        if !question.multiSelect && nextValue {
            selectedOptions[key] = []
        }

        if !nextValue {
            customAnswers[key] = ""
        }
    }

    private func shouldShowNotes(for question: AskUserQuestionPromptItem) -> Bool {
        let key = question.question
        return !(selectedOptions[key] ?? []).isEmpty || customEnabled[key] == true || !(notes[key] ?? "").isEmpty
    }

    private func submitCurrentSelection() {
        guard let submission else { return }
        onSubmit(submission)
    }

    private func binding(
        for key: String,
        in dictionary: Binding<[String: String]>
    ) -> Binding<String> {
        Binding(
            get: { dictionary.wrappedValue[key] ?? "" },
            set: { dictionary.wrappedValue[key] = $0 }
        )
    }
}

private struct MainWindowWizardStepChip: View {
    let title: String
    let index: Int
    let isCurrent: Bool
    let isComplete: Bool
    let isSubmitStep: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: MainWindowTheme.scaled(8)) {
                Image(systemName: iconName)
                    .font(.system(size: MainWindowTheme.scaled(11), weight: .semibold))
                    .foregroundStyle(isCurrent ? Color.black : (isComplete ? TerminalColors.green : MainWindowTheme.textMuted))

                Text(title)
                    .font(.system(size: MainWindowTheme.scaled(12), weight: .semibold))
                    .foregroundStyle(isCurrent ? Color.black : MainWindowTheme.textPrimary)
                    .lineLimit(1)
            }
            .padding(.horizontal, MainWindowTheme.scaled(12))
            .padding(.vertical, MainWindowTheme.scaled(9))
            .background(
                Capsule()
                    .fill(backgroundColor)
                    .overlay(
                        Capsule()
                            .strokeBorder(borderColor, lineWidth: 1)
                    )
                    .shadow(
                        color: isCurrent ? .black.opacity(0.16) : .clear,
                        radius: isCurrent ? 12 : 0,
                        x: 0,
                        y: isCurrent ? 6 : 0
                    )
            )
            .offset(y: isHovered && !isCurrent ? -1 : 0)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(MainWindowTheme.hoverAnimation, value: isHovered)
        .animation(MainWindowTheme.selectionAnimation, value: isCurrent)
        .animation(MainWindowTheme.selectionAnimation, value: isComplete)
    }

    private var iconName: String {
        if isSubmitStep {
            return isComplete ? "checkmark.circle.fill" : "checkmark.circle"
        }
        if isComplete {
            return "checkmark.circle.fill"
        }
        return isCurrent ? "record.circle.fill" : "circle"
    }

    private var backgroundColor: Color {
        if isCurrent {
            return Color.white.opacity(0.96)
        }
        if isComplete {
            return TerminalColors.green.opacity(0.12)
        }
        return Color.white.opacity(0.05)
    }

    private var borderColor: Color {
        if isCurrent {
            return Color.white.opacity(0.98)
        }
        if isComplete {
            return TerminalColors.green.opacity(0.28)
        }
        return Color.white.opacity(0.08)
    }
}

private struct MainWindowQuestionOptionButton: View {
    let leadingLabel: String
    let title: String
    let description: String?
    let isRecommended: Bool
    let isSelected: Bool
    let isMultiSelect: Bool
    let isHovered: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: MainWindowTheme.scaled(12)) {
                Text(leadingLabel)
                    .font(.system(size: MainWindowTheme.scaled(13), weight: .semibold, design: .monospaced))
                    .foregroundStyle(isSelected ? Color.black.opacity(0.78) : MainWindowTheme.textMuted)
                    .frame(width: MainWindowTheme.scaled(28), alignment: .leading)

                VStack(alignment: .leading, spacing: MainWindowTheme.scaled(8)) {
                    HStack(alignment: .top, spacing: MainWindowTheme.scaled(8)) {
                        Image(systemName: selectionIconName)
                            .font(.system(size: MainWindowTheme.scaled(13), weight: .semibold))
                            .foregroundStyle(isSelected ? Color.black : TerminalColors.amber)

                        VStack(alignment: .leading, spacing: MainWindowTheme.scaled(6)) {
                            HStack(spacing: MainWindowTheme.scaled(6)) {
                                Text(title)
                                    .font(.system(size: MainWindowTheme.scaled(13), weight: .semibold))
                                    .foregroundStyle(isSelected ? Color.black : MainWindowTheme.textPrimary)
                                    .multilineTextAlignment(.leading)

                                if isRecommended {
                                    Text("Recommended")
                                        .font(.system(size: MainWindowTheme.scaled(9), weight: .semibold))
                                        .foregroundStyle(isSelected ? Color.black.opacity(0.74) : TerminalColors.amber)
                                        .padding(.horizontal, MainWindowTheme.scaled(7))
                                        .padding(.vertical, MainWindowTheme.scaled(4))
                                        .background(
                                            Capsule()
                                                .fill(isSelected ? Color.black.opacity(0.08) : TerminalColors.amber.opacity(0.14))
                                        )
                                }
                            }

                            if let description, !description.isEmpty {
                                Text(description)
                                    .font(.system(size: MainWindowTheme.scaled(11)))
                                    .foregroundStyle(isSelected ? Color.black.opacity(0.72) : MainWindowTheme.textSecondary)
                                    .multilineTextAlignment(.leading)
                            }
                        }
                    }
                }

                Spacer(minLength: MainWindowTheme.scaled(8))

                if isSelected {
                    Image(systemName: selectionIconName)
                        .font(.system(size: MainWindowTheme.scaled(13), weight: .semibold))
                        .foregroundStyle(Color.black)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, MainWindowTheme.scaled(14))
            .padding(.vertical, MainWindowTheme.scaled(12))
            .background(
                RoundedRectangle(cornerRadius: MainWindowTheme.scaled(16), style: .continuous)
                    .fill(backgroundColor)
                    .overlay(
                        RoundedRectangle(cornerRadius: MainWindowTheme.scaled(16), style: .continuous)
                            .strokeBorder(borderColor, lineWidth: 1)
                    )
                    .shadow(
                        color: isSelected ? TerminalColors.amber.opacity(0.18) : .black.opacity(isHovered ? 0.14 : 0),
                        radius: isSelected ? 16 : (isHovered ? 10 : 0),
                        x: 0,
                        y: isSelected ? 10 : (isHovered ? 5 : 0)
                    )
            )
            .offset(y: isHovered && !isSelected ? -1 : 0)
        }
        .buttonStyle(.plain)
        .animation(MainWindowTheme.hoverAnimation, value: isHovered)
        .animation(MainWindowTheme.selectionAnimation, value: isSelected)
    }

    private var selectionIconName: String {
        if isMultiSelect {
            return isSelected ? "checkmark.circle.fill" : "circle"
        }
        return isSelected ? "largecircle.fill.circle" : "circle"
    }

    private var backgroundColor: Color {
        if isSelected {
            return TerminalColors.amber.opacity(0.92)
        }
        if isHovered {
            return Color.white.opacity(0.08)
        }
        return Color.white.opacity(0.04)
    }

    private var borderColor: Color {
        if isSelected {
            return TerminalColors.amber.opacity(0.96)
        }
        if isRecommended {
            return TerminalColors.amber.opacity(0.22)
        }
        return Color.white.opacity(0.08)
    }
}

private enum MainWindowActionButtonStyle {
    case secondary
    case primary
    case accent
}

private struct MainWindowCardActionButton: View {
    let title: String
    let style: MainWindowActionButtonStyle
    var isEnabled: Bool = true
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: MainWindowTheme.scaled(13), weight: .semibold))
                .foregroundStyle(foregroundColor)
                .padding(.horizontal, MainWindowTheme.scaled(16))
                .padding(.vertical, MainWindowTheme.scaled(10))
                .background(
                    Capsule()
                        .fill(backgroundColor)
                        .overlay(
                            Capsule()
                                .strokeBorder(borderColor, lineWidth: 1)
                        )
                )
                .shadow(color: shadowColor, radius: isHovered ? 12 : 8, x: 0, y: isHovered ? 6 : 4)
                .offset(y: isHovered && isEnabled ? -1 : 0)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .onHover { isHovered = $0 }
        .animation(MainWindowTheme.hoverAnimation, value: isHovered)
        .animation(MainWindowTheme.selectionAnimation, value: isEnabled)
    }

    private var foregroundColor: Color {
        guard isEnabled else { return MainWindowTheme.textMuted }
        switch style {
        case .secondary:
            return MainWindowTheme.textPrimary
        case .primary, .accent:
            return .black
        }
    }

    private var backgroundColor: Color {
        guard isEnabled else { return Color.white.opacity(0.10) }
        switch style {
        case .secondary:
            return isHovered ? Color.white.opacity(0.11) : Color.white.opacity(0.08)
        case .primary:
            return isHovered ? Color.white : Color.white.opacity(0.96)
        case .accent:
            return isHovered ? TerminalColors.amber : TerminalColors.amber.opacity(0.92)
        }
    }

    private var borderColor: Color {
        switch style {
        case .secondary:
            return Color.white.opacity(isHovered ? 0.12 : 0.06)
        case .primary:
            return Color.white.opacity(0.08)
        case .accent:
            return TerminalColors.amber.opacity(0.26)
        }
    }

    private var shadowColor: Color {
        guard isEnabled else { return .clear }
        switch style {
        case .secondary:
            return .black.opacity(0.12)
        case .primary:
            return .black.opacity(0.18)
        case .accent:
            return TerminalColors.amber.opacity(0.18)
        }
    }
}

private struct MainWindowIconActionButton: View {
    let systemImage: String
    let isEnabled: Bool
    let isLoading: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            ZStack {
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .tint(Color.black)
                } else {
                    Image(systemName: systemImage)
                        .font(.system(size: MainWindowTheme.scaled(13), weight: .semibold))
                        .foregroundStyle(isEnabled ? Color.black : MainWindowTheme.textMuted)
                }
            }
            .frame(width: MainWindowTheme.scaled(46), height: MainWindowTheme.scaled(40))
            .background(
                Circle()
                    .fill(isEnabled ? Color.white.opacity(isHovered ? 1 : 0.96) : Color.white.opacity(0.18))
            )
            .shadow(color: isEnabled ? .black.opacity(isHovered ? 0.2 : 0.12) : .clear, radius: isHovered ? 14 : 8, x: 0, y: isHovered ? 7 : 4)
            .offset(y: isHovered && isEnabled ? -1 : 0)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .onHover { isHovered = $0 }
        .animation(MainWindowTheme.hoverAnimation, value: isHovered)
        .animation(MainWindowTheme.selectionAnimation, value: isEnabled)
    }
}

private struct MainWindowStreamingStatusRow: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var pulseOpacity = 0.86

    var body: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)

            Text("Claude is responding...")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(MainWindowTheme.textSecondary.opacity(pulseOpacity))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(Color.white.opacity(0.04))
                .overlay(
                    Capsule()
                        .strokeBorder(Color.white.opacity(0.07), lineWidth: 1)
                )
        )
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                pulseOpacity = 0.46
            }
        }
    }
}
