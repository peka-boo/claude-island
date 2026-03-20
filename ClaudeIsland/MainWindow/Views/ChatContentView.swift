//
//  ChatContentView.swift
//  ClaudeIsland
//
//  Chat area showing messages, streaming content, and input field.
//

import SwiftUI

struct ChatContentView: View {
    @Bindable var viewModel: ChatViewModel
    let threadId: String

    var body: some View {
        VStack(spacing: 0) {
            // Header
            chatHeader

            Divider()

            // Messages
            messageList

            Divider()

            // Input
            MessageInputView(
                text: $viewModel.inputText,
                isProcessing: viewModel.isProcessing,
                onSend: { Task { await viewModel.sendMessage() } },
                onInterrupt: { Task { await viewModel.interrupt() } }
            )
        }
        .background(Color(.windowBackgroundColor))
        .task(id: threadId) {
            await viewModel.loadThread(threadId)
        }
    }

    // MARK: - Header

    private var chatHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(viewModel.threadInfo?.title ?? "New Chat")
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)

                if let branch = viewModel.threadInfo?.gitBranch {
                    HStack(spacing: 3) {
                        Image(systemName: "arrow.triangle.branch")
                            .font(.system(size: 10))
                        Text(branch)
                            .font(.system(size: 11))
                    }
                    .foregroundStyle(.secondary)
                }
            }

            Spacer()

            // Cost badge
            if let cost = viewModel.threadInfo?.totalCostUsd, cost > 0 {
                HStack(spacing: 3) {
                    Image(systemName: "dollarsign.circle")
                        .font(.system(size: 10))
                    Text(String(format: "$%.4f", cost))
                        .font(.system(size: 11, design: .monospaced))
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(.quaternary.opacity(0.5))
                .clipShape(Capsule())
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }

    // MARK: - Message List

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(viewModel.messages) { message in
                        MessageBubbleView(message: message)
                            .id(message.id)
                    }

                    // Streaming content
                    if viewModel.isStreaming {
                        streamingBubble
                            .id("streaming")
                    }

                    // Error
                    if let error = viewModel.error {
                        errorBubble(error)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .onChange(of: viewModel.messages.count) { _, _ in
                withAnimation(.easeOut(duration: 0.2)) {
                    if viewModel.isStreaming {
                        proxy.scrollTo("streaming", anchor: .bottom)
                    } else if let lastId = viewModel.messages.last?.id {
                        proxy.scrollTo(lastId, anchor: .bottom)
                    }
                }
            }
            .onChange(of: viewModel.currentStreamingText) { _, _ in
                withAnimation(.easeOut(duration: 0.1)) {
                    proxy.scrollTo("streaming", anchor: .bottom)
                }
            }
        }
    }

    // MARK: - Streaming Bubble

    private var streamingBubble: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Thinking
            if !viewModel.currentThinkingText.isEmpty {
                DisclosureGroup {
                    Text(viewModel.currentThinkingText)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "brain")
                            .font(.system(size: 11))
                        Text("Thinking...")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundStyle(.purple)
                }
            }

            // Streaming text
            if !viewModel.currentStreamingText.isEmpty {
                Text(viewModel.currentStreamingText)
                    .font(.system(size: 13))
                    .textSelection(.enabled)
            }

            // Processing indicator
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.small)
                Text("Claude is working...")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.purple.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Error Bubble

    private func errorBubble(_ message: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(.red)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.red.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
