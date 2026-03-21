//
//  WelcomeView.swift
//  ClaudeIsland
//
//  Empty state view shown when no thread is selected.
//

import SwiftUI

struct WelcomeView: View {
    let onNewChat: (String) -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            // Icon
            ZStack {
                Circle()
                    .fill(TerminalColors.amber.opacity(0.1))
                    .frame(width: 80, height: 80)

                Image(systemName: "sparkles")
                    .font(.system(size: 36))
                    .foregroundStyle(TerminalColors.amber)
            }

            // Title
            VStack(spacing: 8) {
                Text("Claude Island")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                Text("Start a conversation or select one from the sidebar")
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
            }

            // Quick Actions
            VStack(spacing: 12) {
                Button {
                    selectFolder()
                } label: {
                    Label("New Conversation", systemImage: "plus.bubble.fill")
                        .font(.system(size: 14, weight: .medium))
                        .frame(width: 200)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(TerminalColors.blue)

                HStack(spacing: 16) {
                    quickActionButton(
                        icon: "keyboard",
                        title: "⌘N",
                        subtitle: "New Chat"
                    )
                    quickActionButton(
                        icon: "command",
                        title: "⌘⏎",
                        subtitle: "Send"
                    )
                    quickActionButton(
                        icon: "escape",
                        title: "⌘.",
                        subtitle: "Stop"
                    )
                }
                .padding(.top, 8)
            }

            Spacer()

            // Version info
            if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
                Text("Claude Island v\(version)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.3))
                    .padding(.bottom, 16)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(red: 0.08, green: 0.08, blue: 0.09))
        .preferredColorScheme(.dark)
    }

    private func quickActionButton(icon: String, title: String, subtitle: String) -> some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.6))
            Text(subtitle)
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.4))
        }
        .frame(width: 70)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
        )
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
