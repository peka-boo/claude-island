import Foundation

@inline(__always)
func assertDetachedSettings(
    _ condition: @autoclosure () -> Bool,
    _ message: String
) {
    if !condition() {
        fputs("Assertion failed: \(message)\n", stderr)
        exit(1)
    }
}

@main
struct DetachedResumeSettingsSupportTestRunner {
    static func main() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("detached-resume-settings-support-\(UUID().uuidString)", isDirectory: true)
        let home = root.appendingPathComponent("home", isDirectory: true)
        let cwd = root.appendingPathComponent("workspace", isDirectory: true)
        let userClaudeDir = home.appendingPathComponent(".claude", isDirectory: true)
        let projectClaudeDir = cwd.appendingPathComponent(".claude", isDirectory: true)

        try fileManager.createDirectory(at: userClaudeDir, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: projectClaudeDir, withIntermediateDirectories: true)

        try writeJSON(
            [
                "env": [
                    "ANTHROPIC_AUTH_TOKEN": "user-token",
                    "ANTHROPIC_BASE_URL": "https://example.invalid",
                ],
                "enabledPlugins": [
                    "everything-claude-code@everything-claude-code": true,
                ],
                "hooks": [
                    "Notification": [
                        [
                            "matcher": "",
                            "hooks": [
                                [
                                    "type": "command",
                                    "command": "~/.claude-island/hooks/hook-sender.sh",
                                ],
                            ],
                        ],
                    ],
                ],
                "model": "opus",
            ],
            to: userClaudeDir.appendingPathComponent("settings.json")
        )

        try writeJSON(
            [
                "permissions": [
                    "allow": [
                        "Bash(git:*)",
                    ],
                ],
                "enabledPlugins": [
                    "glm-plan-bug@zai-coding-plugins": true,
                ],
            ],
            to: userClaudeDir.appendingPathComponent("settings.local.json")
        )

        try writeJSON(
            [
                "env": [
                    "PROJECT_ONLY": "1",
                ],
                "hooks": [
                    "SessionStart": [
                        [
                            "matcher": "",
                            "hooks": [
                                [
                                    "type": "command",
                                    "command": "echo should-not-run",
                                ],
                            ],
                        ],
                    ],
                ],
                "enabledPlugins": [
                    "everything-claude-code@everything-claude-code": false,
                ],
            ],
            to: projectClaudeDir.appendingPathComponent("settings.json")
        )

        try writeJSON(
            [
                "model": "sonnet",
                "enabledPlugins": [
                    "local-only-plugin@example": true,
                ],
            ],
            to: projectClaudeDir.appendingPathComponent("settings.local.json")
        )

        let sanitized = try DetachedResumeSettingsSupport.sanitizedSettings(
            cwd: cwd.path,
            homeDirectory: home,
            fileManager: fileManager
        )

        assertDetachedSettings(
            sanitized["hooks"] == nil,
            "sanitized settings must remove all hooks from detached resume launches"
        )

        let env = sanitized["env"] as? [String: String]
        assertDetachedSettings(
            env?["ANTHROPIC_AUTH_TOKEN"] == "user-token",
            "user env values should be preserved for authentication"
        )
        assertDetachedSettings(
            env?["PROJECT_ONLY"] == "1",
            "project env values should still be merged in"
        )

        let plugins = sanitized["enabledPlugins"] as? [String: Bool]
        assertDetachedSettings(
            plugins?["everything-claude-code@everything-claude-code"] == false,
            "project settings should override user plugin values"
        )
        assertDetachedSettings(
            plugins?["glm-plan-bug@zai-coding-plugins"] == true,
            "user local settings should be merged in"
        )
        assertDetachedSettings(
            plugins?["local-only-plugin@example"] == true,
            "project local settings should be merged in"
        )

        assertDetachedSettings(
            sanitized["model"] as? String == "sonnet",
            "project local settings should win for scalar overrides"
        )

        let settingsFileURL = try DetachedResumeSettingsSupport.writeSanitizedSettingsFile(
            cwd: cwd.path,
            homeDirectory: home,
            fileManager: fileManager
        )
        let fileData = try Data(contentsOf: settingsFileURL)
        let fileJSON = try JSONSerialization.jsonObject(with: fileData) as? [String: Any]

        assertDetachedSettings(
            fileJSON?["hooks"] == nil,
            "serialized detached settings file should also stay hook-free"
        )

        DetachedResumeSettingsSupport.removeSanitizedSettingsFile(
            at: settingsFileURL,
            fileManager: fileManager
        )
        assertDetachedSettings(
            !fileManager.fileExists(atPath: settingsFileURL.path),
            "temporary detached settings files should be removable after launch"
        )

        try? fileManager.removeItem(at: root)
        print("detached resume settings support checks passed")
    }

    private static func writeJSON(_ json: [String: Any], to url: URL) throws {
        let data = try JSONSerialization.data(withJSONObject: json, options: [.sortedKeys])
        try data.write(to: url, options: .atomic)
    }
}
