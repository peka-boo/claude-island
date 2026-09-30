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
    @State private var hookDisplayMode = AppSettings.claudeHookDisplayMode
    @State private var hookMonitorEnabled = AppSettings.hookMonitorEnabled
    @State private var notificationSound = AppSettings.notificationSound

    var body: some View {
        Form {
            Section("claude-message") {
                Picker("claude hook", selection: $hookDisplayMode) {
                    ForEach(ClaudeHookDisplayMode.allCases, id: \.self) { mode in
                        Text(ClaudeMessageDisplaySupport.menuTitle(for: mode)).tag(mode)
                    }
                }
                .pickerStyle(.inline)
                .onChange(of: hookDisplayMode) { _, newValue in
                    AppSettings.setClaudeHookDisplayMode(newValue)
                }

                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "gearshape.fill")
                        .foregroundStyle(.orange)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("claude hook")
                            .font(.system(size: 13, weight: .medium))
                        Text("Popup is the default. Current Notch only runs when you explicitly select it.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
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
                    HookMonitorCoordinator.setEnabled(
                        newValue,
                        persist: { enabled in
                            AppSettings.setHookMonitorEnabled(enabled)
                        },
                        installHooks: {
                            HookInstaller.installIfNeeded()
                        },
                        uninstallHooks: {
                            HookInstaller.uninstall()
                        },
                        monitorController: ClaudeSessionMonitor.shared
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
        .onReceive(NotificationCenter.default.publisher(for: .notchToggled)) { _ in
            syncFromSettings()
        }
        .onReceive(NotificationCenter.default.publisher(for: .desktopMessageToggled)) { _ in
            syncFromSettings()
        }
        .onReceive(NotificationCenter.default.publisher(for: .hookMonitorToggled)) { _ in
            syncFromSettings()
        }
    }

    private func syncFromSettings() {
        hookDisplayMode = AppSettings.claudeHookDisplayMode
        hookMonitorEnabled = AppSettings.hookMonitorEnabled
        notificationSound = AppSettings.notificationSound
    }
}
