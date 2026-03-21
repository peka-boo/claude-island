//
//  AppSettingsView.swift
//  ClaudeIsland
//
//  Settings panel accessible via ⌘, (macOS standard).
//  Controls Notch toggle, Hook Monitor toggle, notification sounds, etc.
//

import SwiftUI
import Sparkle

struct AppSettingsView: View {
    @State private var notchEnabled = AppSettings.notchEnabled
    @State private var hookMonitorEnabled = AppSettings.hookMonitorEnabled
    @State private var notificationSound = AppSettings.notificationSound

    var body: some View {
        Form {
            // Dynamic Island
            Section {
                Toggle(isOn: $notchEnabled) {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Dynamic Island (Notch)")
                                .font(.system(size: 13, weight: .medium))
                            Text("Show session status in the Notch area")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "sparkle.magnifyingglass")
                            .foregroundStyle(.purple)
                    }
                }
                .onChange(of: notchEnabled) { _, newValue in
                    AppSettings.notchEnabled = newValue
                    NotificationCenter.default.post(
                        name: .notchToggled,
                        object: nil,
                        userInfo: ["enabled": newValue]
                    )
                }
            }

            // Hook Monitor
            Section {
                Toggle(isOn: $hookMonitorEnabled) {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Hook Monitor")
                                .font(.system(size: 13, weight: .medium))
                            Text("Monitor all Claude Code sessions across terminals")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "globe")
                            .foregroundStyle(.blue)
                    }
                }
                .onChange(of: hookMonitorEnabled) { _, newValue in
                    AppSettings.hookMonitorEnabled = newValue
                    NotificationCenter.default.post(
                        name: .hookMonitorToggled,
                        object: nil,
                        userInfo: ["enabled": newValue]
                    )
                }
            } footer: {
                Text("When enabled, installs a hook script into ~/.claude/settings.json to capture events from all CLI sessions. Starts a local HTTP server on port \(AppSettings.serverPort).")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            // Notification Sound
            Section {
                Picker(selection: $notificationSound) {
                    ForEach(NotificationSound.allCases, id: \.self) { sound in
                        Text(sound.rawValue).tag(sound)
                    }
                } label: {
                    Label {
                        Text("Notification Sound")
                            .font(.system(size: 13, weight: .medium))
                    } icon: {
                        Image(systemName: "bell.fill")
                            .foregroundStyle(.orange)
                    }
                }
                .onChange(of: notificationSound) { _, newValue in
                    AppSettings.notificationSound = newValue
                    // Play preview
                    if let name = newValue.soundName {
                        NSSound(named: NSSound.Name(name))?.play()
                    }
                }
            }

            // About
            Section("About") {
                LabeledContent("Version") {
                    Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—")
                        .font(.system(size: 12, design: .monospaced))
                }

                LabeledContent("Build") {
                    Text(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—")
                        .font(.system(size: 12, design: .monospaced))
                }

                Button("Check for Updates") {
                    AppDelegate.shared?.updater.checkForUpdates()
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 450, height: 420)
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let notchToggled = Notification.Name("notchToggled")
    static let hookMonitorToggled = Notification.Name("hookMonitorToggled")
}
