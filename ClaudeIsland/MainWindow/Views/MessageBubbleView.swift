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
        HStack(alignment: .top, spacing: 8) {
            // Avatar
            avatar

            VStack(alignment: .leading, spacing: 4) {
                // Role label
                Text(roleLabel)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(roleColor)

                // Thinking (collapsible)
                if let thinking = message.thinking, !thinking.isEmpty {
                    DisclosureGroup {
                        Text(thinking)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .padding(.vertical, 4)
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "brain")
                                .font(.system(size: 10))
                            Text("Reasoning")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .foregroundStyle(.purple)
                    }
                    .padding(.bottom, 2)
                }

                // Tool use
                if let toolName = message.toolName {
                    toolBadge(name: toolName, input: message.toolInput)
                }

                // Main content
                if !message.content.isEmpty && message.toolName == nil {
                    Text(message.content)
                        .font(.system(size: 13))
                        .textSelection(.enabled)
                        .lineSpacing(2)
                }

                // Tool result
                if let result = message.toolResult {
                    toolResultView(result)
                }

                // Metadata
                metadataRow
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(bubbleBackground)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Avatar

    private var avatar: some View {
        ZStack {
            Circle()
                .fill(roleColor.opacity(0.15))
                .frame(width: 28, height: 28)

            Image(systemName: avatarIcon)
                .font(.system(size: 13))
                .foregroundStyle(roleColor)
        }
    }

    // MARK: - Tool Badge

    private func toolBadge(name: String, input: String?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: toolIcon(for: name))
                    .font(.system(size: 10))
                Text(name)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
            }
            .foregroundStyle(.orange)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.orange.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 6))

            if let input = input, !input.isEmpty, input != "{}" {
                Text(input)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .padding(.horizontal, 8)
            }
        }
    }

    // MARK: - Tool Result

    private func toolResultView(_ result: String) -> some View {
        Text(result)
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(.secondary)
            .lineLimit(5)
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.3))
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    // MARK: - Metadata

    private var metadataRow: some View {
        HStack(spacing: 8) {
            Text(message.createdAt, style: .time)
                .font(.system(size: 10))
                .foregroundStyle(.quaternary)

            if let cost = message.costUsd, cost > 0 {
                Text(String(format: "$%.4f", cost))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.quaternary)
            }

            if let tokensIn = message.tokensIn, let tokensOut = message.tokensOut {
                Text("\(tokensIn)↓ \(tokensOut)↑")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.quaternary)
            }
        }
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
        case .user: return .blue
        case .assistant: return .purple
        case .system: return .gray
        }
    }

    private var avatarIcon: String {
        switch message.role {
        case .user: return "person.fill"
        case .assistant: return "sparkles"
        case .system: return "gearshape.fill"
        }
    }

    private var bubbleBackground: Color {
        switch message.role {
        case .user: return .blue.opacity(0.06)
        case .assistant: return .purple.opacity(0.04)
        case .system: return .gray.opacity(0.06)
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
        default: return "wrench"
        }
    }
}
