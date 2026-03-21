//
//  MessageBubbleView.swift
//  ClaudeIsland
//
//  Renders a single message bubble (user, assistant, or system).
//  Supports text, thinking disclosure, and tool use display.
//

import SwiftUI

struct MessageBubbleView: View {
    let message: MessageDTO

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Avatar
            avatar

            VStack(alignment: .leading, spacing: 4) {
                // Role label
                Text(roleLabel)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(roleColor)
                    .padding(.bottom, 2)

                // Thinking (collapsible)
                if let thinking = message.thinking, !thinking.isEmpty {
                    DisclosureGroup {
                        Text(thinking)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.5))
                            .textSelection(.enabled)
                            .padding(.vertical, 4)
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "brain")
                                .font(.system(size: 10))
                            Text("Reasoning")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .foregroundStyle(TerminalColors.magenta)
                    }
                    .padding(.bottom, 4)
                }

                // Tool use
                if let toolName = message.toolName {
                    toolBadge(name: toolName, input: message.toolInput)
                }

                // Main content
                if !message.content.isEmpty && message.toolName == nil {
                    Text(message.content)
                        .font(.system(size: 13))
                        .foregroundStyle(message.role == .user ? .white : .white.opacity(0.9))
                        .textSelection(.enabled)
                        .lineSpacing(4)
                }

                // Tool result
                if let result = message.toolResult {
                    toolResultView(result)
                }

                // Metadata
                metadataRow
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(bubbleBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Avatar

    private var avatar: some View {
        ZStack {
            if message.role == .assistant {
                // Use ClaudeCrabIcon for assistant if available or just sparkles
                Circle()
                    .fill(TerminalColors.amber.opacity(0.15))
                    .frame(width: 28, height: 28)
                Image(systemName: "sparkles")
                    .font(.system(size: 12))
                    .foregroundStyle(TerminalColors.amber)
            } else if message.role == .user {
                Circle()
                    .fill(Color.white.opacity(0.1))
                    .frame(width: 28, height: 28)
                Image(systemName: "person.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.8))
            } else {
                Circle()
                    .fill(Color.white.opacity(0.05))
                    .frame(width: 28, height: 28)
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
        .padding(.top, 2)
    }

    // MARK: - Tool Badge

    private func toolBadge(name: String, input: String?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: toolIcon(for: name))
                    .font(.system(size: 10))
                Text(name)
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
            }
            .foregroundStyle(TerminalColors.amber)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(TerminalColors.amber.opacity(0.15))
            .clipShape(RoundedRectangle(cornerRadius: 6))

            if let input = input, !input.isEmpty, input != "{}" {
                Text(input)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(4)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.black.opacity(0.2))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - Tool Result

    private func toolResultView(_ result: String) -> some View {
        Text(result)
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(.white.opacity(0.6))
            .lineLimit(8)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.black.opacity(0.3))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.white.opacity(0.05), lineWidth: 1)
            )
            .padding(.top, 4)
    }

    // MARK: - Metadata

    private var metadataRow: some View {
        HStack(spacing: 8) {
            Text(message.createdAt, style: .time)
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.3))

            if let cost = message.costUsd, cost > 0 {
                Text(String(format: "$%.4f", cost))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.3))
            }

            if let tokensIn = message.tokensIn, let tokensOut = message.tokensOut {
                Text("\(tokensIn)↓ \(tokensOut)↑")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.3))
            }
        }
        .padding(.top, 6)
    }

    // MARK: - Styling

    private var roleLabel: String {
        switch message.role {
        case .user: return "You"
        case .assistant: return "Claude"
        case .system: return "System"
        }
    }

    private var roleColor: Color {
        switch message.role {
        case .user: return .white.opacity(0.8)
        case .assistant: return TerminalColors.amber
        case .system: return .white.opacity(0.5)
        }
    }

    private var bubbleBackground: Color {
        switch message.role {
        case .user: return Color.white.opacity(0.05)
        case .assistant: return TerminalColors.background
        case .system: return Color.white.opacity(0.02)
        }
    }

    private func toolIcon(for name: String) -> String {
        switch name.lowercased() {
        case "read", "view": return "doc.text"
        case "write", "edit": return "pencil"
        case "bash", "execute": return "terminal"
        case "glob", "find": return "magnifyingglass"
        case "grep", "search": return "text.magnifyingglass"
        case "websearch": return "globe"
        case "webfetch": return "arrow.down.doc"
        default: return "wrench.fill"
        }
    }
}
