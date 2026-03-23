//
//  ClaudeMessageWindowManager.swift
//  ClaudeIsland
//
//  Drives the hook-triggered popup surface used by claude-message Popup mode.
//

import AppKit
import Foundation
import SwiftUI

private struct ClaudeHookPopupPresentation {
    let title: String
    let subtitle: String
    let detail: String?
    let badge: String
    let tone: ClaudeHookPopupTone
    let actionTitle: String
    let keepsVisible: Bool
}

private enum ClaudeHookPopupTone {
    case activity
    case attention
    case ready
    case ended

    var color: Color {
        switch self {
        case .activity:
            return Color(red: 0.46, green: 0.65, blue: 0.98)
        case .attention:
            return MainWindowTheme.accent
        case .ready:
            return Color(red: 0.33, green: 0.83, blue: 0.56)
        case .ended:
            return MainWindowTheme.textMuted
        }
    }
}

private final class ClaudeHookPopupPanel: NSPanel {
    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        titlebarAppearsTransparent = true
        titleVisibility = .hidden
        isFloatingPanel = true
        level = .statusBar
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovableByWindowBackground = false
        hidesOnDeactivate = false
        animationBehavior = .utilityWindow
        collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .stationary,
            .ignoresCycle,
            .fullScreenDisallowsTiling
        ]
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override var isExcludedFromWindowsMenu: Bool {
        get { true }
        set { }
    }
}

@MainActor
final class ClaudeHookPopupManager {
    static let shared = ClaudeHookPopupManager()

    private let panelWidth: CGFloat = 336
    private let edgeInset: CGFloat = 40
    private let verticalInset: CGFloat = 44
    private let minimumDisplayDuration: TimeInterval = 2.2

    private var panel: ClaudeHookPopupPanel?
    private var dismissTask: Task<Void, Never>?

    private init() {
        NotificationCenter.default.addObserver(
            forName: .desktopMessageToggled,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.syncVisibilityWithSettings()
            }
        }

        NotificationCenter.default.addObserver(
            forName: .notchToggled,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.syncVisibilityWithSettings()
            }
        }

        NotificationCenter.default.addObserver(
            forName: .hookMonitorToggled,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.syncVisibilityWithSettings()
            }
        }
    }

    func handleHookEvent(_ event: HookEvent, session: SessionState?) {
        guard shouldUsePopup,
              shouldPresentPopup(for: event, session: session),
              let presentation = makePresentation(for: event, session: session) else {
            hide()
            return
        }

        show(presentation, autoDismissAfter: dismissalDelay(for: event, session: session, keepsVisible: presentation.keepsVisible))
    }

    func hide() {
        dismissTask?.cancel()
        dismissTask = nil
        panel?.orderOut(nil)
    }

    private var shouldUsePopup: Bool {
        AppSettings.hookMonitorEnabled && AppSettings.claudeHookDisplayMode == .popup
    }

    private func syncVisibilityWithSettings() {
        guard shouldUsePopup else {
            hide()
            return
        }

        if let session = ClaudeSessionMonitor.shared.pendingInstances.first ?? ClaudeSessionMonitor.shared.instances.last,
           let presentation = makePresentation(for: nil, session: session) {
            show(
                presentation,
                autoDismissAfter: dismissalDelay(for: nil, session: session, keepsVisible: presentation.keepsVisible)
            )
        } else {
            hide()
        }
    }

    private func show(_ presentation: ClaudeHookPopupPresentation, autoDismissAfter delay: TimeInterval?) {
        dismissTask?.cancel()
        dismissTask = nil

        let panel = ensurePanel()
        let contentView = NSHostingView(
            rootView: ClaudeHookPopupView(
                presentation: presentation,
                onOpen: { [weak self] in
                    self?.openMainWindow()
                },
                onDismiss: { [weak self] in
                    self?.hide()
                }
            )
            .frame(width: panelWidth)
        )

        contentView.frame = NSRect(x: 0, y: 0, width: panelWidth, height: 10)
        contentView.layoutSubtreeIfNeeded()
        let contentSize = contentView.fittingSize
        panel.contentView = contentView
        panel.setContentSize(contentSize)
        panel.setFrame(frame(for: contentSize), display: true)
        panel.orderFrontRegardless()

        guard let delay else { return }

        let dismissalDelayNs = UInt64(max(delay, minimumDisplayDuration) * 1_000_000_000)
        dismissTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: dismissalDelayNs)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self?.hide()
            }
        }
    }

    private func ensurePanel() -> ClaudeHookPopupPanel {
        if let panel {
            return panel
        }

        let panel = ClaudeHookPopupPanel()
        self.panel = panel
        return panel
    }

    private func frame(for size: CGSize) -> NSRect {
        let screenFrame = NSScreen.main?.visibleFrame ?? NSScreen.screens.first?.visibleFrame ?? .zero
        return NSRect(
            x: screenFrame.maxX - size.width - edgeInset,
            y: screenFrame.minY + verticalInset,
            width: size.width,
            height: size.height
        )
    }

    private func dismissalDelay(for event: HookEvent?, session: SessionState?, keepsVisible: Bool) -> TimeInterval? {
        if keepsVisible {
            return nil
        }

        switch event?.event {
        case "UserPromptSubmit":
            return 2.2
        case "PreToolUse", "PostToolUse", "PostToolUseFailure", "SubagentStart", "SubagentStop":
            return 2.5
        case "Stop", "SessionEnd":
            return 2.8
        default:
            if session?.phase == .processing {
                return 2.4
            }
            return 2.8
        }
    }

    private func shouldPresentPopup(for event: HookEvent, session: SessionState?) -> Bool {
        if event.event == "Notification",
           event.notificationType == "idle_prompt",
           session?.needsAttention != true {
            return false
        }

        return true
    }

    private func makePresentation(for event: HookEvent?, session: SessionState?) -> ClaudeHookPopupPresentation? {
        let projectName = session?.projectName ?? event?.projectName ?? "Claude Hook"
        let title = projectName.isEmpty ? "Claude Hook" : projectName

        let subtitle: String
        let tone: ClaudeHookPopupTone
        let keepsVisible: Bool

        switch session?.phase {
        case .waitingForApproval(let context):
            if context.toolName == "AskUserQuestion" {
                subtitle = "Claude needs your reply"
            } else {
                subtitle = "Waiting for approval"
            }
            tone = .attention
            keepsVisible = true

        case .waitingForInput:
            subtitle = "Waiting for your input"
            tone = .ready
            keepsVisible = true

        case .processing:
            if let toolName = event?.tool ?? session?.lastToolName {
                subtitle = "Running \(toolName)"
            } else {
                subtitle = "Claude is working"
            }
            tone = .activity
            keepsVisible = false

        case .compacting:
            subtitle = "Compacting context"
            tone = .activity
            keepsVisible = false

        case .ended:
            subtitle = "Session ended"
            tone = .ended
            keepsVisible = false

        case .idle, nil:
            if event?.event == "SessionEnd" || event?.status == "ended" {
                subtitle = "Session ended"
                tone = .ended
            } else if event?.event == "UserPromptSubmit" {
                subtitle = "Message sent"
                tone = .activity
            } else if event?.event == "Stop" {
                subtitle = "Claude stopped"
                tone = .ended
            } else {
                subtitle = "Hook received"
                tone = .activity
            }
            keepsVisible = false
        }

        let detail = popupDetail(for: event, session: session, title: title)
        let badge = popupBadge(for: event, session: session)
        let actionTitle = popupActionTitle(for: session)

        return ClaudeHookPopupPresentation(
            title: title,
            subtitle: subtitle,
            detail: detail,
            badge: badge,
            tone: tone,
            actionTitle: actionTitle,
            keepsVisible: keepsVisible
        )
    }

    private func popupActionTitle(for session: SessionState?) -> String {
        switch session?.phase {
        case .waitingForApproval:
            return "Open Approval"
        case .waitingForInput:
            return "Open Reply"
        default:
            return "Open Claude Island"
        }
    }

    private func popupBadge(for event: HookEvent?, session: SessionState?) -> String {
        if let event {
            return readableHookEventName(event.event)
        }

        switch session?.phase {
        case .waitingForApproval:
            return "Permission"
        case .waitingForInput:
            return "Ready"
        case .processing:
            return "Running"
        case .compacting:
            return "Compacting"
        case .ended:
            return "Ended"
        case .idle, nil:
            return "Claude Hook"
        }
    }

    private func popupDetail(for event: HookEvent?, session: SessionState?, title: String) -> String? {
        if let pendingTool = session?.pendingToolName {
            return pendingTool
        }

        if let tool = event?.tool, !tool.isEmpty {
            return tool
        }

        if let summary = session?.displayTitle,
           !summary.isEmpty,
           summary != title {
            return summary
        }

        if let lastMessage = session?.lastMessage?.trimmedPopupText,
           !lastMessage.isEmpty {
            return lastMessage
        }

        if let cwd = event?.cwd {
            return URL(fileURLWithPath: cwd).lastPathComponent
        }

        return nil
    }

    private func readableHookEventName(_ eventName: String) -> String {
        switch eventName {
        case "PermissionRequest":
            return "Permission"
        case "PreToolUse":
            return "Tool Start"
        case "PostToolUse":
            return "Tool Done"
        case "PostToolUseFailure":
            return "Tool Failed"
        case "UserPromptSubmit":
            return "Prompt"
        case "SessionStart":
            return "Session Start"
        case "SessionEnd":
            return "Session End"
        case "SubagentStart":
            return "Subagent Start"
        case "SubagentStop":
            return "Subagent Stop"
        default:
            return eventName
        }
    }

    private func openMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        if let mainWindow = NSApp.windows.first(where: { $0.title == "Claude Island" }) {
            mainWindow.makeKeyAndOrderFront(nil)
        } else {
            NSApp.windows.first?.makeKeyAndOrderFront(nil)
        }
        hide()
    }
}

private struct ClaudeHookPopupView: View {
    let presentation: ClaudeHookPopupPresentation
    let onOpen: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 10) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(presentation.tone.color)
                        .frame(width: 9, height: 9)

                    Text("claude hook")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(MainWindowTheme.textSecondary)
                }

                Spacer()

                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(MainWindowTheme.textMuted)
                        .frame(width: 24, height: 24)
                        .background(MainWindowTheme.panelElevated)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(presentation.title)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(MainWindowTheme.textPrimary)
                    .lineLimit(2)

                Text(presentation.subtitle)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(presentation.tone.color)
                    .lineLimit(2)

                if let detail = presentation.detail {
                    Text(detail)
                        .font(.system(size: 12))
                        .foregroundStyle(MainWindowTheme.textSecondary)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(spacing: 10) {
                Text(presentation.badge)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(MainWindowTheme.textPrimary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(MainWindowTheme.panelElevated)
                    .clipShape(Capsule())

                Spacer()

                Button(presentation.actionTitle, action: onOpen)
                    .buttonStyle(.borderedProminent)
                    .tint(presentation.tone.color)
            }
        }
        .padding(18)
        .mainWindowCard(
            fill: MainWindowTheme.sidebarPanel.opacity(0.985),
            border: MainWindowTheme.borderStrong,
            radius: 24,
            shadowOpacity: 0.34
        )
        .padding(4)
    }
}

private extension HookEvent {
    var projectName: String {
        URL(fileURLWithPath: cwd).lastPathComponent
    }
}

private extension String {
    var trimmedPopupText: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
