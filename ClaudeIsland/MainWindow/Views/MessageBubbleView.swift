//
//  MessageBubbleView.swift
//  ClaudeIsland
//
//  Open transcript styling with minimal containers.
//

import SwiftUI

struct MessageBubbleView: View {
    let message: MessageDTO
    @State private var isThinkingExpanded = false
    @State private var isToolResultExpanded = false
    @State private var isUserHovered = false
    @State private var isToolHovered = false
    @State private var isResultHovered = false

    var body: some View {
        Group {
            switch message.role {
            case .user:
                userMessage
            case .assistant:
                assistantMessage
            case .system:
                systemMessage
            }
        }
        .textSelection(.enabled)
    }

    private var userMessage: some View {
        HStack {
            Spacer(minLength: 140)

            VStack(alignment: .trailing, spacing: 8) {
                if !message.content.isEmpty {
                    MarkdownText(message.content, color: MainWindowTheme.textPrimary, fontSize: 15)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 13)
                        .background(
                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .fill(isUserHovered ? Color.white.opacity(0.13) : Color.white.opacity(0.10))
                                .shadow(color: .black.opacity(isUserHovered ? 0.16 : 0.08), radius: isUserHovered ? 16 : 8, x: 0, y: isUserHovered ? 8 : 4)
                        )
                        .offset(y: isUserHovered ? -1 : 0)
                        .onHover { isUserHovered = $0 }
                        .animation(MainWindowTheme.hoverAnimation, value: isUserHovered)
                }

                metadataRow(alignment: .trailing)
            }
        }
    }

    private var assistantMessage: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let thinking = message.thinking, !thinking.isEmpty {
                DisclosureGroup(isExpanded: $isThinkingExpanded) {
                    MarkdownText(thinking, color: MainWindowTheme.textSecondary, fontSize: 12)
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
                .animation(MainWindowTheme.panelOpenAnimation, value: isThinkingExpanded)
            }

            if let toolName = message.toolName {
                toolBadge(name: toolName, input: message.toolInput)
            }

            if !message.content.isEmpty {
                MarkdownText(message.content, color: MainWindowTheme.textPrimary, fontSize: 15)
            }

            if let result = message.toolResult, !result.isEmpty {
                toolResultView(result)
            }

            metadataRow(alignment: .leading)
        }
        .frame(maxWidth: MainWindowTheme.conversationColumnMaxWidth, alignment: .leading)
    }

    private var systemMessage: some View {
        HStack {
            Spacer()

            Text(message.content)
                .font(.system(size: 12))
                .foregroundStyle(MainWindowTheme.textSecondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    Capsule()
                        .fill(Color.white.opacity(0.05))
                )

            Spacer()
        }
    }

    private func toolBadge(name: String, input: String?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: toolIcon(for: name))
                    .font(.system(size: 11, weight: .medium))
                Text(name)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
            }
            .foregroundStyle(MainWindowTheme.accent)

            if let input = input, !input.isEmpty, input != "{}" {
                Text(input)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(MainWindowTheme.textSecondary)
                    .lineLimit(6)
                    .textSelection(.enabled)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(isToolHovered ? Color.white.opacity(0.06) : Color.white.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                )
                .shadow(color: .black.opacity(isToolHovered ? 0.16 : 0.08), radius: isToolHovered ? 14 : 8, x: 0, y: isToolHovered ? 8 : 4)
        )
        .offset(y: isToolHovered ? -1 : 0)
        .onHover { isToolHovered = $0 }
        .animation(MainWindowTheme.hoverAnimation, value: isToolHovered)
    }

    private func toolResultView(_ result: String) -> some View {
        let presentation = ChatToolResultPresentationSupport.presentation(for: result)

        return VStack(alignment: .leading, spacing: 10) {
            if presentation.shouldCollapse {
                Button {
                    withAnimation(MainWindowTheme.panelOpenAnimation) {
                        isToolResultExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: isToolResultExpanded ? "doc.text.fill" : "doc.text")
                            .font(.system(size: 11, weight: .medium))
                        Text(presentation.collapseTitle)
                            .font(.system(size: 12, weight: .semibold))

                        Spacer(minLength: 12)

                        Text("\(presentation.lineCount) lines")
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundStyle(MainWindowTheme.textMuted)

                        Image(systemName: isToolResultExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundStyle(MainWindowTheme.textPrimary)
                }
                .buttonStyle(.plain)

                if isToolResultExpanded {
                    ScrollView([.vertical, .horizontal], showsIndicators: true) {
                        Text(presentation.fullText)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(MainWindowTheme.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                            .textSelection(.enabled)
                    }
                    .frame(maxHeight: 320)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        Text(presentation.previewText)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(MainWindowTheme.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                            .textSelection(.enabled)
                    }

                    if presentation.hiddenLineCount > 0 {
                        Text("Hidden \(presentation.hiddenLineCount) more lines")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(MainWindowTheme.textMuted)
                            .padding(.horizontal, 14)
                    }
                }
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    Text(presentation.fullText)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(MainWindowTheme.textSecondary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .textSelection(.enabled)
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(isResultHovered ? Color.white.opacity(0.05) : Color.white.opacity(0.03))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.07), lineWidth: 1)
                )
                .shadow(color: .black.opacity(isResultHovered ? 0.14 : 0.06), radius: isResultHovered ? 12 : 6, x: 0, y: isResultHovered ? 6 : 3)
        )
        .offset(y: isResultHovered ? -1 : 0)
        .onHover { isResultHovered = $0 }
        .animation(MainWindowTheme.hoverAnimation, value: isResultHovered)
        .animation(MainWindowTheme.panelOpenAnimation, value: isToolResultExpanded)
    }

    @ViewBuilder
    private func metadataRow(alignment: HorizontalAlignment) -> some View {
        let row = HStack(spacing: 10) {
            Text(message.createdAt, style: .time)

            if let cost = message.costUsd, cost > 0 {
                Text(String(format: "$%.4f", cost))
            }

            if let tokensIn = message.tokensIn, let tokensOut = message.tokensOut {
                Text("\(tokensIn)↓ \(tokensOut)↑")
            }
        }
        .font(.system(size: 10, design: .monospaced))
        .foregroundStyle(MainWindowTheme.textMuted)

        switch alignment {
        case .trailing:
            HStack { Spacer(); row }
        default:
            row
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
        default: return "wrench.adjustable"
        }
    }
}
