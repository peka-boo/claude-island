//
//  WelcomeView.swift
//  ClaudeIsland
//
//  Empty state for the main window.
//

import SwiftUI

struct WelcomeView: View {
    let onNewChat: (String) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showHero = false
    @State private var showActions = false
    @State private var showFooter = false
    @State private var isCreateHovered = false

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            VStack(spacing: 20) {
                ZStack {
                    Circle()
                        .fill(MainWindowTheme.accent.opacity(0.18))
                        .frame(width: 96, height: 96)
                        .scaleEffect(showHero ? 1 : 0.92)
                        .opacity(showHero ? 1 : 0)

                    ClaudeCrabIcon(size: 34, color: MainWindowTheme.accent)
                        .scaleEffect(showHero ? 1 : 0.88)
                        .opacity(showHero ? 1 : 0)
                }

                VStack(spacing: 10) {
                    Text("Bring a Claude session back into focus")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(MainWindowTheme.textPrimary)
                        .multilineTextAlignment(.center)

                    Text("Create a workspace thread, restore an imported session, or keep working in an existing project without losing context.")
                        .font(.system(size: 14))
                        .foregroundStyle(MainWindowTheme.textSecondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 520)
                }
                .opacity(showHero ? 1 : 0)
                .offset(y: showHero ? 0 : 10)

                HStack(spacing: 12) {
                    Button {
                        selectFolder()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "plus")
                                .font(.system(size: 12, weight: .bold))
                            Text("Create Thread")
                                .font(.system(size: 14, weight: .semibold))
                        }
                        .foregroundStyle(.black)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 12)
                        .background(Color.white.opacity(0.95))
                        .clipShape(Capsule())
                        .shadow(
                            color: .black.opacity(isCreateHovered ? 0.22 : 0.12),
                            radius: isCreateHovered ? 16 : 10,
                            x: 0,
                            y: isCreateHovered ? 8 : 4
                        )
                        .offset(y: isCreateHovered ? -1 : 0)
                    }
                    .buttonStyle(.plain)
                    .onHover { isCreateHovered = $0 }
                    .animation(MainWindowTheme.hoverAnimation, value: isCreateHovered)

                    shortcutPill("Cmd+Return", subtitle: "Send")
                    shortcutPill("Cmd+.", subtitle: "Interrupt")
                    shortcutPill("Cmd+Shift+K", subtitle: "Terminate")
                }
                .opacity(showActions ? 1 : 0)
                .offset(y: showActions ? 0 : 12)
            }
            .padding(32)
            .mainWindowCard(
                fill: Color.black.opacity(0.18),
                border: MainWindowTheme.borderStrong,
                radius: 28
            )
            .opacity(showHero ? 1 : 0)
            .offset(y: showHero ? 0 : 14)

            Spacer()

            if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
                Text("Claude Island v\(version)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(MainWindowTheme.textMuted)
                    .opacity(showFooter ? 1 : 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
        .task {
            if reduceMotion {
                showHero = true
                showActions = true
                showFooter = true
                return
            }

            withAnimation(MainWindowTheme.panelOpenAnimation) {
                showHero = true
            }
            withAnimation(MainWindowTheme.contentSwapAnimation.delay(0.06)) {
                showActions = true
            }
            withAnimation(MainWindowTheme.softFadeAnimation.delay(0.12)) {
                showFooter = true
            }
        }
    }

    private func shortcutPill(_ title: String, subtitle: String) -> some View {
        WelcomeShortcutPill(title: title, subtitle: subtitle)
    }

    private func selectFolder() {
        let panel = NSOpenPanel()
        panel.title = "Select Working Directory"
        panel.message = "Choose a project folder for the new Claude conversation"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = false
        panel.allowsMultipleSelection = false

        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            onNewChat(url.path)
        }
    }
}

private struct WelcomeShortcutPill: View {
    let title: String
    let subtitle: String

    @State private var isHovered = false

    var body: some View {
        VStack(spacing: 5) {
            Text(title)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(MainWindowTheme.textPrimary)
            Text(subtitle)
                .font(.system(size: 10))
                .foregroundStyle(MainWindowTheme.textSecondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .mainWindowCard(
            fill: isHovered ? MainWindowTheme.panelElevated : MainWindowTheme.panel,
            border: isHovered ? MainWindowTheme.borderStrong : MainWindowTheme.border,
            radius: 16,
            shadowOpacity: isHovered ? 0.12 : 0
        )
        .offset(y: isHovered ? -1 : 0)
        .onHover { isHovered = $0 }
        .animation(MainWindowTheme.hoverAnimation, value: isHovered)
    }
}
