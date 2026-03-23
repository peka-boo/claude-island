//
//  ComposerCommandSupport.swift
//  ClaudeIsland
//
//  Shared slash-command and composer parsing helpers for the main window.
//

import Foundation

struct ComposerCommandSuggestion: Identifiable, Equatable, Sendable {
    let command: String
    let description: String
    let insertsTrailingSpace: Bool

    var id: String { command }
    var label: String { String(command.dropFirst()) }
}

enum ComposerLocalCommand: Equatable, Sendable {
    case help
    case clear
    case rename(String)
}

enum ComposerSubmitAction: Equatable, Sendable {
    case send(String)
    case local(ComposerLocalCommand)
}

enum ComposerCommandLogic {
    static func slashQuery(in text: String) -> String? {
        let range = text.range(
            of: "(^|\\s)/([^\\s/]*)$",
            options: .regularExpression
        )

        guard let range else { return nil }
        let matched = String(text[range])
        guard let slashIndex = matched.lastIndex(of: "/") else { return nil }
        return String(matched[matched.index(after: slashIndex)...])
    }

    static func filteredCommands(
        from commands: [ComposerCommandSuggestion],
        query: String
    ) -> [ComposerCommandSuggestion] {
        guard !query.isEmpty else { return commands }

        let lowered = query.lowercased()
        return commands.filter { item in
            item.command.lowercased().contains(lowered) ||
            item.description.lowercased().contains(lowered)
        }
    }

    static func submitAction(for text: String) -> ComposerSubmitAction? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let renameTitle = renameTitle(from: trimmed) {
            return .local(.rename(renameTitle))
        }

        switch trimmed {
        case "/help":
            return .local(.help)
        case "/clear":
            return .local(.clear)
        default:
            return .send(trimmed)
        }
    }

    static func insertableText(for command: ComposerCommandSuggestion) -> String {
        command.command + (command.insertsTrailingSpace ? " " : "")
    }

    static func shouldSubmitPaletteSelection(
        text: String,
        selectedCommand: ComposerCommandSuggestion?
    ) -> Bool {
        guard let selectedCommand else { return false }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed == selectedCommand.command
    }

    private static func renameTitle(from input: String) -> String? {
        if input.lowercased().hasPrefix("claude rename ") {
            let title = String(input.dropFirst("claude rename ".count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return title.isEmpty ? nil : title
        }

        if input.hasPrefix("/rename ") {
            let title = String(input.dropFirst("/rename ".count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return title.isEmpty ? nil : title
        }

        return nil
    }
}

enum SessionCommandCatalog {
    static let builtIn: [ComposerCommandSuggestion] = [
        ComposerCommandSuggestion(
            command: "/help",
            description: "Show available commands and input tips",
            insertsTrailingSpace: false
        ),
        ComposerCommandSuggestion(
            command: "/rename",
            description: "Rename the current session title",
            insertsTrailingSpace: true
        ),
        ComposerCommandSuggestion(
            command: "/clear",
            description: "Clear current thread messages and reset resume state",
            insertsTrailingSpace: false
        )
    ]

    static func load(cwd: String?) -> [ComposerCommandSuggestion] {
        var merged: [String: ComposerCommandSuggestion] = [:]

        for command in builtIn {
            merged[command.command] = command
        }

        for command in scanCommands(in: homeCommandsDirectoryURL) {
            merged[command.command] = command
        }

        if let cwd {
            for command in scanCommands(in: URL(fileURLWithPath: cwd).appendingPathComponent(".claude/commands")) {
                merged[command.command] = command
            }
        }

        return merged.values.sorted { lhs, rhs in
            lhs.command.localizedCaseInsensitiveCompare(rhs.command) == .orderedAscending
        }
    }

    static let helpMarkdown = """
    ## Available Commands

    - `/help` Show this help message
    - `/rename <title>` Rename the current session
    - `/clear` Clear current thread history and resume state
    - Type `/` to browse real local commands from `~/.claude/commands` and `.claude/commands`
    - Claude CLI subcommands like `doctor`, `mcp`, and `update` are terminal commands, not chat slash commands
    - Press `Enter` to send, `Shift+Enter` for a new line
    """

    private static var homeCommandsDirectoryURL: URL {
        homeDirectoryURL.appendingPathComponent(".claude/commands")
    }

    private static var homeDirectoryURL: URL {
        if let home = Foundation.ProcessInfo.processInfo.environment["HOME"], !home.isEmpty {
            return URL(fileURLWithPath: home, isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
    }

    private static func scanCommands(in directory: URL) -> [ComposerCommandSuggestion] {
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }

        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var suggestions: [ComposerCommandSuggestion] = []

        for case let url as URL in enumerator {
            guard url.pathExtension == "md" else { continue }

            let relativePath = url.path
                .replacingOccurrences(of: directory.path + "/", with: "")
            let name = relativePath
                .replacingOccurrences(of: ".md", with: "")
                .replacingOccurrences(of: "\\", with: "/")

            guard !name.isEmpty else { continue }

            suggestions.append(
                ComposerCommandSuggestion(
                    command: "/" + name,
                    description: firstDescriptionLine(in: url) ?? "Custom Claude command",
                    insertsTrailingSpace: true
                )
            )
        }

        return suggestions
    }

    private static func firstDescriptionLine(in url: URL) -> String? {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else {
            return nil
        }

        for line in content.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("description:") {
                return trimmed.replacingOccurrences(of: "description:", with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            }

            if trimmed.isEmpty || trimmed == "---" || trimmed.hasPrefix("#") {
                continue
            }

            return trimmed
        }

        return nil
    }
}
