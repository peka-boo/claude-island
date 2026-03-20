//
//  HookInstaller.swift
//  ClaudeIsland
//
//  Installs Claude Code hooks using Bash + HTTP (replaces Python + Unix Socket).
//  Reference: Masko Code's HookInstaller.swift
//

import Foundation

struct HookInstaller {

    // MARK: - Paths

    private static let claudeSettingsPath: String = {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/settings.json").path
    }()

    private static let hookScriptDir: String = {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude-island/hooks").path
    }()

    private static let hookScriptPath: String = {
        hookScriptDir + "/hook-sender.sh"
    }()

    private static let hookCommand = "~/.claude-island/hooks/hook-sender.sh"

    /// Legacy Python script to clean up
    private static let legacyPythonScriptPath: String = {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/hooks/claude-island-state.py").path
    }()

    /// All Claude Code event types we subscribe to
    private static let hookEvents = [
        "PreToolUse",
        "PostToolUse",
        "PostToolUseFailure",
        "Stop",
        "Notification",
        "SessionStart",
        "SessionEnd",
        "TaskCompleted",
        "PermissionRequest",
        "UserPromptSubmit",
        "SubagentStart",
        "SubagentStop",
        "PreCompact",
    ]

    // MARK: - Script Version

    private static let scriptVersion = "# version: 1"

    // MARK: - Public API

    /// Install hook script and register in settings.json on app launch
    static func installIfNeeded() {
        // Clean up legacy Python hook first
        cleanupLegacyHooks()

        // Ensure Bash script exists and is up to date
        ensureScriptExists()

        // Register hooks in settings.json
        registerHooks()
    }

    /// Check if hooks are currently installed
    static func isInstalled() -> Bool {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: claudeSettingsPath)),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let hooks = json["hooks"] as? [String: Any] else {
            return false
        }

        for event in hookEvents {
            if let entries = hooks[event] as? [[String: Any]],
               entries.contains(where: { entry in
                   guard let innerHooks = entry["hooks"] as? [[String: Any]] else { return false }
                   return innerHooks.contains { ($0["command"] as? String) == hookCommand }
               }) {
                return true
            }
        }
        return false
    }

    /// Uninstall hooks from settings.json and remove script
    static func uninstall() {
        // Remove hook registrations
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: claudeSettingsPath)),
              var json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              var hooks = json["hooks"] as? [String: Any] else {
            return
        }

        for event in hookEvents {
            guard var entries = hooks[event] as? [[String: Any]] else { continue }
            entries.removeAll { entry in
                guard let innerHooks = entry["hooks"] as? [[String: Any]] else { return false }
                return innerHooks.contains { ($0["command"] as? String) == hookCommand }
            }
            if entries.isEmpty {
                hooks.removeValue(forKey: event)
            } else {
                hooks[event] = entries
            }
        }

        if hooks.isEmpty {
            json.removeValue(forKey: "hooks")
        } else {
            json["hooks"] = hooks
        }

        writeSettings(json)

        // Remove script file
        try? FileManager.default.removeItem(atPath: hookScriptPath)
    }

    // MARK: - Private

    /// Create or update the Bash hook-sender.sh script
    private static func ensureScriptExists() {
        let scriptURL = URL(fileURLWithPath: hookScriptPath)
        let port = AppSettings.serverPort

        // Check if existing script is up to date
        if FileManager.default.fileExists(atPath: hookScriptPath),
           let contents = try? String(contentsOf: scriptURL, encoding: .utf8),
           contents.contains(scriptVersion),
           contents.contains("localhost:\(port)") {
            return // Already up to date
        }

        // Create directory
        try? FileManager.default.createDirectory(
            atPath: hookScriptDir,
            withIntermediateDirectories: true
        )

        // Read the bundled template and replace port placeholder
        var script: String
        if let bundledURL = Bundle.main.url(forResource: "hook-sender", withExtension: "sh"),
           let template = try? String(contentsOf: bundledURL, encoding: .utf8) {
            script = template.replacingOccurrences(of: "__PORT__", with: "\(port)")
        } else {
            // Fallback: minimal inline script
            script = """
            #!/bin/bash
            \(scriptVersion)
            curl -s --connect-timeout 0.3 "http://localhost:\(port)/health" >/dev/null 2>&1 || exit 0
            INPUT=$(cat 2>/dev/null || echo '{}')
            curl -s -X POST -H "Content-Type: application/json" -d "$INPUT" \
              "http://localhost:\(port)/hook" --connect-timeout 1 --max-time 2 2>/dev/null || true
            exit 0
            """
        }

        try? script.write(toFile: hookScriptPath, atomically: true, encoding: .utf8)

        // Make executable
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: hookScriptPath
        )
    }

    /// Register hook entries in ~/.claude/settings.json
    private static func registerHooks() {
        var json: [String: Any] = [:]
        if let data = try? Data(contentsOf: URL(fileURLWithPath: claudeSettingsPath)),
           let existing = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            json = existing
        }

        var hooks = json["hooks"] as? [String: Any] ?? [:]

        // Build hook entry — PermissionRequest gets a timeout
        for event in hookEvents {
            var entries = hooks[event] as? [[String: Any]] ?? []

            // Skip if our hook is already registered
            let alreadyRegistered = entries.contains { entry in
                guard let innerHooks = entry["hooks"] as? [[String: Any]] else { return false }
                return innerHooks.contains { ($0["command"] as? String) == hookCommand }
            }
            if alreadyRegistered { continue }

            let hookConfig: [String: Any]
            if event == "PermissionRequest" {
                hookConfig = ["type": "command", "command": hookCommand, "timeout": 86400]
            } else {
                hookConfig = ["type": "command", "command": hookCommand]
            }

            let entry: [String: Any] = [
                "matcher": "",
                "hooks": [hookConfig],
            ]
            entries.append(entry)
            hooks[event] = entries
        }

        json["hooks"] = hooks

        // Ensure ~/.claude/ directory exists
        let claudeDir = (claudeSettingsPath as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(
            atPath: claudeDir,
            withIntermediateDirectories: true
        )

        writeSettings(json)
    }

    /// Clean up legacy Python hook script and registrations
    private static func cleanupLegacyHooks() {
        // Remove legacy Python script
        try? FileManager.default.removeItem(atPath: legacyPythonScriptPath)

        // Remove legacy hook registrations from settings.json
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: claudeSettingsPath)),
              var json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              var hooks = json["hooks"] as? [String: Any] else {
            return
        }

        var changed = false
        for (event, value) in hooks {
            guard var entries = value as? [[String: Any]] else { continue }
            let before = entries.count
            entries.removeAll { entry in
                guard let innerHooks = entry["hooks"] as? [[String: Any]] else { return false }
                return innerHooks.contains { hook in
                    let cmd = hook["command"] as? String ?? ""
                    return cmd.contains("claude-island-state.py")
                }
            }
            if entries.count != before {
                changed = true
                if entries.isEmpty {
                    hooks.removeValue(forKey: event)
                } else {
                    hooks[event] = entries
                }
            }
        }

        if changed {
            json["hooks"] = hooks.isEmpty ? nil : hooks
            writeSettings(json)
        }
    }

    private static func writeSettings(_ settings: [String: Any]) {
        if let data = try? JSONSerialization.data(
            withJSONObject: settings,
            options: [.prettyPrinted, .sortedKeys]
        ) {
            try? data.write(to: URL(fileURLWithPath: claudeSettingsPath))
        }
    }
}
