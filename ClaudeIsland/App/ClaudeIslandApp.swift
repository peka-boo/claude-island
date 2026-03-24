//
//  ClaudeIslandApp.swift
//  ClaudeIsland
//
//  Claude Island — Full Claude Code client with Dynamic Island overlay.
//

import SwiftUI
import SwiftData

@main
struct ClaudeIslandApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    /// Shared CLI session manager for subprocess lifecycle
    static let cliManager: CLIManaging = CLISessionManager.shared

    var body: some Scene {
        // Main Window — opens by default on launch
        Window("Claude Island", id: "main") {
            MainContentView(cliManager: Self.cliManager)
                .modelContainer(DataStore.shared)
        }
        .defaultSize(width: 1100, height: 720)
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified(showsTitle: true))
        .commands {
            // New Chat shortcut
            CommandGroup(after: .newItem) {
                Button("New Conversation") {
                    NotificationCenter.default.post(name: .newConversation, object: nil)
                }
                .keyboardShortcut("n", modifiers: .command)
            }
        }

        // Settings — standard ⌘, shortcut
        Settings {
            AppSettingsView()
        }
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let newConversation = Notification.Name("newConversation")
}
