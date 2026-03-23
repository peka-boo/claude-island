//
//  MessageInputView.swift
//  ClaudeIsland
//
//  Compact composer with slash-command palette and Enter-to-send behavior.
//

import SwiftUI

struct MessageInputView: View {
    @Binding var text: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let commands: [ComposerCommandSuggestion]
    let isProcessing: Bool
    let processingDescriptor: ComposerProcessingDescriptor?
    let canTerminate: Bool
    let onSend: () -> Void
    let onInterrupt: () -> Void
    let onTerminate: () -> Void

    @State private var composerHeight = MainWindowTheme.scaled(46)
    @State private var selectedCommandIndex = 0
    @State private var isHovered = false

    private var trimmedText: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var slashQuery: String? {
        ComposerCommandLogic.slashQuery(in: text)
    }

    private var filteredCommands: [ComposerCommandSuggestion] {
        guard let slashQuery else { return [] }
        return ComposerCommandLogic.filteredCommands(from: commands, query: slashQuery)
    }

    private var isShowingCommandPalette: Bool {
        slashQuery != nil && !filteredCommands.isEmpty
    }

    private var boundedComposerHeight: CGFloat {
        min(max(composerHeight, MainWindowTheme.scaled(46)), MainWindowTheme.scaled(112))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: MainWindowTheme.scaled(10)) {
            if isShowingCommandPalette {
                commandPalette
                    .transition(MainWindowTheme.adaptiveTransition(MainWindowTheme.floatingCardTransition, reduceMotion: reduceMotion))
            }

            ZStack(alignment: .topLeading) {
                if text.isEmpty {
                    Text("Message Claude...  (`/` for commands)")
                        .font(.system(size: MainWindowTheme.scaled(15)))
                        .foregroundStyle(MainWindowTheme.textMuted)
                        .padding(.horizontal, MainWindowTheme.scaled(14))
                        .padding(.top, MainWindowTheme.scaled(12))
                }

                ComposerTextView(
                    text: $text,
                    isEditable: !isProcessing,
                    isCommandPaletteVisible: isShowingCommandPalette,
                    onSubmit: {
                        guard !isProcessing else { return }
                        onSend()
                    },
                    onMoveCommandSelection: moveCommandSelection,
                    onConfirmCommandSelection: confirmSelectedCommand,
                    onDismissCommandSelection: dismissCommandPalette,
                    onHeightChange: { measuredHeight in
                        composerHeight = measuredHeight
                    }
                )
                .frame(height: boundedComposerHeight)
                .padding(.horizontal, MainWindowTheme.scaled(14))
            }

            footer
        }
        .padding(.horizontal, MainWindowTheme.scaled(14))
        .padding(.top, MainWindowTheme.scaled(14))
        .padding(.bottom, MainWindowTheme.scaled(14))
        .background(
            RoundedRectangle(cornerRadius: MainWindowTheme.scaled(24), style: .continuous)
                .fill(isShowingCommandPalette ? MainWindowTheme.panelElevated : Color.white.opacity(0.035))
                .overlay(
                    RoundedRectangle(cornerRadius: MainWindowTheme.scaled(24), style: .continuous)
                        .strokeBorder(isShowingCommandPalette ? MainWindowTheme.borderStrong : Color.white.opacity(0.11), lineWidth: 1)
                )
                .shadow(
                    color: .black.opacity(isHovered || isShowingCommandPalette ? 0.22 : 0.14),
                    radius: isHovered || isShowingCommandPalette ? 26 : 16,
                    y: isHovered || isShowingCommandPalette ? 16 : 10
                )
        )
        .offset(y: isHovered ? -1 : 0)
        .onHover { isHovered = $0 }
        .animation(MainWindowTheme.adaptiveAnimation(MainWindowTheme.panelOpenAnimation, reduceMotion: reduceMotion), value: isShowingCommandPalette)
        .animation(MainWindowTheme.adaptiveAnimation(MainWindowTheme.hoverAnimation, reduceMotion: reduceMotion), value: isHovered)
        .onChange(of: slashQuery) { _, _ in
            selectedCommandIndex = 0
        }
    }

    private var commandPalette: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(filteredCommands.enumerated()), id: \.element.id) { index, command in
                Button {
                    insertCommand(command)
                } label: {
                    HStack(spacing: MainWindowTheme.scaled(10)) {
                        Text(command.command)
                            .font(.system(size: MainWindowTheme.scaled(13), weight: .semibold))
                            .foregroundStyle(MainWindowTheme.textPrimary)

                        Text(command.description)
                            .font(.system(size: MainWindowTheme.scaled(12)))
                            .foregroundStyle(MainWindowTheme.textSecondary)
                            .lineLimit(1)

                        Spacer()
                    }
                    .padding(.horizontal, MainWindowTheme.scaled(12))
                    .padding(.vertical, MainWindowTheme.scaled(10))
                    .background(
                        RoundedRectangle(cornerRadius: MainWindowTheme.scaled(12), style: .continuous)
                            .fill(index == selectedCommandIndex ? MainWindowTheme.panelSelected : Color.clear)
                            .overlay(
                                RoundedRectangle(cornerRadius: MainWindowTheme.scaled(12), style: .continuous)
                                    .strokeBorder(index == selectedCommandIndex ? Color.white.opacity(0.08) : Color.clear, lineWidth: 1)
                            )
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(MainWindowTheme.scaled(6))
        .background(
            RoundedRectangle(cornerRadius: MainWindowTheme.scaled(18), style: .continuous)
                .fill(Color(red: 0.10, green: 0.09, blue: 0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: MainWindowTheme.scaled(18), style: .continuous)
                        .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.28), radius: 20, x: 0, y: 12)
        )
    }

    private var footer: some View {
        HStack(alignment: .center, spacing: MainWindowTheme.scaled(10)) {
            HStack(spacing: MainWindowTheme.scaled(8)) {
                ComposerMiniButton(icon: "plus") {}
                ComposerMiniButton(icon: "slash.circle") {
                    insertSlashTrigger()
                }
                ComposerMiniButton(icon: "terminal") {}
            }

            footerStateContent

            Spacer()

            ComposerSendButton(
                isEnabled: !trimmedText.isEmpty && !isProcessing,
                action: onSend
            )
        }
    }

    private var footerStateContent: some View {
        Group {
            if let processingDescriptor, isProcessing {
                HStack(alignment: .center, spacing: MainWindowTheme.scaled(10)) {
                    ComposerProcessingStatusView(descriptor: processingDescriptor)

                    ComposerLabelPill(
                        title: "Interrupt",
                        accent: TerminalColors.amber,
                        action: onInterrupt
                    )

                    ComposerLabelPill(
                        title: "Terminate",
                        accent: TerminalColors.red,
                        action: onTerminate
                    )
                    .disabled(!canTerminate)
                }
                .transition(.opacity)
            } else {
                Text("Enter to send, Shift+Enter for new line")
                    .font(.system(size: MainWindowTheme.scaled(12)))
                    .foregroundStyle(MainWindowTheme.textSecondary)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, minHeight: MainWindowTheme.scaled(34), alignment: .leading)
        .animation(
            MainWindowTheme.adaptiveAnimation(MainWindowTheme.contentSwapAnimation, reduceMotion: reduceMotion),
            value: isProcessing
        )
    }

    private func insertSlashTrigger() {
        if text.isEmpty {
            text = "/"
            return
        }

        if text.hasSuffix(" ") || text.hasSuffix("\n") {
            text.append("/")
        } else {
            text.append(" /")
        }
    }

    private func moveCommandSelection(_ delta: Int) {
        guard !filteredCommands.isEmpty else { return }
        let nextIndex = (selectedCommandIndex + delta + filteredCommands.count) % filteredCommands.count
        selectedCommandIndex = nextIndex
    }

    private func insertSelectedCommand() {
        guard filteredCommands.indices.contains(selectedCommandIndex) else { return }
        insertCommand(filteredCommands[selectedCommandIndex])
    }

    private func confirmSelectedCommand() {
        guard filteredCommands.indices.contains(selectedCommandIndex) else { return }

        let selectedCommand = filteredCommands[selectedCommandIndex]
        if ComposerCommandLogic.shouldSubmitPaletteSelection(
            text: text,
            selectedCommand: selectedCommand
        ) {
            guard !isProcessing else { return }
            onSend()
            return
        }

        insertCommand(selectedCommand)
    }

    private func dismissCommandPalette() {
        guard let slashQuery else { return }
        guard let range = text.range(
            of: "(^|\\s)/\(NSRegularExpression.escapedPattern(for: slashQuery))$",
            options: .regularExpression
        ) else {
            return
        }

        let matched = String(text[range])
        if matched.hasPrefix(" ") {
            text.replaceSubrange(range, with: " ")
        } else {
            text.removeSubrange(range)
        }
    }

    private func insertCommand(_ command: ComposerCommandSuggestion) {
        let insertText = ComposerCommandLogic.insertableText(for: command)

        if let range = text.range(
            of: "(^|\\s)/([^\\s/]*)$",
            options: .regularExpression
        ) {
            let matched = String(text[range])
            let replacement = matched.hasPrefix(" ") ? " " + insertText : insertText
            text.replaceSubrange(range, with: replacement)
        } else {
            if !text.isEmpty, !text.hasSuffix(" "), !text.hasSuffix("\n") {
                text.append(" ")
            }
            text.append(insertText)
        }
    }
}

private struct ComposerProcessingStatusView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let descriptor: ComposerProcessingDescriptor

    var body: some View {
        HStack(spacing: MainWindowTheme.scaled(10)) {
            ComposerActivityIndicator(reduceMotion: reduceMotion)

            VStack(alignment: .leading, spacing: MainWindowTheme.scaled(2)) {
                Text(descriptor.title)
                    .font(.system(size: MainWindowTheme.scaled(12), weight: .semibold))
                    .foregroundStyle(MainWindowTheme.textPrimary)

                Text(descriptor.detail)
                    .font(.system(size: MainWindowTheme.scaled(10)))
                    .foregroundStyle(MainWindowTheme.textSecondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, MainWindowTheme.scaled(12))
        .padding(.vertical, MainWindowTheme.scaled(8))
        .background(
            RoundedRectangle(cornerRadius: MainWindowTheme.scaled(14), style: .continuous)
                .fill(Color.white.opacity(0.045))
                .overlay(
                    RoundedRectangle(cornerRadius: MainWindowTheme.scaled(14), style: .continuous)
                        .strokeBorder(Color.white.opacity(0.07), lineWidth: 1)
                )
        )
    }
}

private struct ComposerActivityIndicator: View {
    let reduceMotion: Bool

    @State private var activeIndex = 0

    var body: some View {
        HStack(spacing: MainWindowTheme.scaled(4)) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(index == activeIndex ? TerminalColors.green : TerminalColors.green.opacity(0.28))
                    .frame(width: MainWindowTheme.scaled(6), height: MainWindowTheme.scaled(6))
                    .scaleEffect(index == activeIndex ? 1 : 0.82)
            }
        }
        .frame(width: MainWindowTheme.scaled(28), alignment: .leading)
        .task(id: reduceMotion) {
            guard !reduceMotion else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(240))
                await MainActor.run {
                    activeIndex = (activeIndex + 1) % 3
                }
            }
        }
    }
}

private struct ComposerMiniButton: View {
    let icon: String
    var action: () -> Void = {}
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: MainWindowTheme.scaled(14), weight: .medium))
                .foregroundStyle(MainWindowTheme.textSecondary)
                .frame(width: MainWindowTheme.scaled(28), height: MainWindowTheme.scaled(28))
                .background(
                    RoundedRectangle(cornerRadius: MainWindowTheme.scaled(8), style: .continuous)
                        .fill(isHovered ? MainWindowTheme.hoverFill : Color.clear)
                )
                .offset(y: isHovered ? -1 : 0)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(MainWindowTheme.hoverAnimation, value: isHovered)
    }
}

private struct ComposerLabelPill: View {
    let title: String
    let accent: Color
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: MainWindowTheme.scaled(13), weight: .medium))
                .foregroundStyle(accent)
                .padding(.horizontal, MainWindowTheme.scaled(12))
                .padding(.vertical, MainWindowTheme.scaled(7))
                .background(
                    Capsule()
                        .fill(isHovered ? accent.opacity(0.18) : accent.opacity(0.12))
                )
                .overlay(
                    Capsule()
                        .strokeBorder(accent.opacity(isHovered ? 0.24 : 0), lineWidth: 1)
                )
                .offset(y: isHovered ? -1 : 0)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(MainWindowTheme.hoverAnimation, value: isHovered)
    }
}

private struct ComposerSendButton: View {
    let isEnabled: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "arrow.up")
                .font(.system(size: MainWindowTheme.scaled(16), weight: .semibold))
                .foregroundStyle(isEnabled ? .white : MainWindowTheme.textMuted)
                .frame(width: MainWindowTheme.scaled(42), height: MainWindowTheme.scaled(42))
                .background(
                    Circle()
                        .fill(isEnabled ? TerminalColors.blue.opacity(isHovered ? 0.92 : 0.82) : Color.white.opacity(0.06))
                )
                .shadow(
                    color: isEnabled ? TerminalColors.blue.opacity(isHovered ? 0.34 : 0.22) : .clear,
                    radius: isHovered ? 14 : 10,
                    y: isHovered ? 8 : 5
                )
                .offset(y: isHovered && isEnabled ? -1 : 0)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .onHover { isHovered = $0 }
        .animation(MainWindowTheme.hoverAnimation, value: isHovered)
        .animation(MainWindowTheme.selectionAnimation, value: isEnabled)
    }
}
