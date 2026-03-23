//
//  CLIPermissionFallback.swift
//  ClaudeIsland
//
//  Main-window fallback approval detection for Claude CLI print-mode.
//  Some CLI turns emit an approval failure as a normal tool_result instead of
//  surfacing a live PermissionRequest hook. This helper synthesizes a local
//  approval card so the UI can still offer an actionable choice.
//

import Foundation

struct LocalCLIPermissionRequest: Equatable, Sendable, Identifiable {
    let toolUseId: String
    let toolName: String
    let toolInputJSON: String
    let formattedInput: String?
    let retryPrompt: String
    let cliSessionId: String?

    var id: String { toolUseId }
}

struct CLIPermissionFallbackTracker: Equatable, Sendable {
    private struct ToolUseContext: Equatable, Sendable {
        let id: String
        let name: String
        let inputJSON: String
    }

    private var latestToolUse: ToolUseContext?
    private(set) var pendingRequest: LocalCLIPermissionRequest?

    mutating func consume(
        _ event: CLIStreamEvent,
        originalPrompt: String,
        cliSessionId: String?
    ) {
        switch event {
        case .toolUse(let id, let name, let input):
            latestToolUse = ToolUseContext(id: id, name: name, inputJSON: input)
            if name == "AskUserQuestion" {
                pendingRequest = LocalCLIPermissionRequest(
                    toolUseId: id,
                    toolName: name,
                    toolInputJSON: input,
                    formattedInput: Self.formatToolInput(input),
                    retryPrompt: "",
                    cliSessionId: normalizeCLISessionId(cliSessionId)
                )
            }

        case .toolResult(let id, _, let output):
            if let pending = pendingRequest,
               pending.toolUseId == id,
               pending.toolName == "AskUserQuestion" {
                if Self.isAskUserQuestionCompletion(output) {
                    pendingRequest = nil
                } else if Self.isAskUserQuestionAwaitingResponse(output) {
                    return
                }
            }

            guard Self.isApprovalFailure(output) else { return }

            let tool = (latestToolUse?.id == id ? latestToolUse : nil) ??
                ToolUseContext(id: id, name: "unknown", inputJSON: "{}")

            pendingRequest = LocalCLIPermissionRequest(
                toolUseId: tool.id,
                toolName: tool.name,
                toolInputJSON: tool.inputJSON,
                formattedInput: Self.formatToolInput(tool.inputJSON),
                retryPrompt: Self.makeRetryPrompt(
                    toolName: tool.name,
                    formattedInput: Self.formatToolInput(tool.inputJSON),
                    originalPrompt: originalPrompt
                ),
                cliSessionId: normalizeCLISessionId(cliSessionId)
            )

        default:
            break
        }
    }

    mutating func clearPendingRequest() {
        pendingRequest = nil
    }

    mutating func reset() {
        latestToolUse = nil
        pendingRequest = nil
    }

    nonisolated static func parseToolInputJSONObject(_ inputJSON: String) -> [String: Any]? {
        guard let data = inputJSON.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let dictionary = object as? [String: Any] else {
            return nil
        }
        return dictionary
    }

    private nonisolated static func isApprovalFailure(_ output: String) -> Bool {
        let normalized = output.lowercased()
        let approvalPhrases = [
            "this command requires approval",
            "this tool requires approval",
            "requires your approval",
            "requires approval:",
            "requested permissions to",
            "haven't granted it yet"
        ]

        return approvalPhrases.contains { normalized.contains($0) }
    }

    private nonisolated static func isAskUserQuestionAwaitingResponse(_ output: String) -> Bool {
        let normalized = output.lowercased()
        return normalized.contains("answer questions?")
    }

    private nonisolated static func isAskUserQuestionCompletion(_ output: String) -> Bool {
        let normalized = output.lowercased()
        return normalized.contains("user has answered your questions:")
    }

    nonisolated static func makeAskUserQuestionFollowUpPrompt(_ responseText: String) -> String {
        let trimmed = responseText.trimmingCharacters(in: .whitespacesAndNewlines)
        return "User has answered your questions: \(trimmed). You can now continue with the user's answers in mind."
    }

    private nonisolated static func formatToolInput(_ inputJSON: String) -> String? {
        guard let dictionary = parseToolInputJSONObject(inputJSON), !dictionary.isEmpty else {
            return nil
        }

        let lines = dictionary.keys.sorted().compactMap { key -> String? in
            guard let value = dictionary[key] else { return nil }
            let rendered = renderValue(value)
            guard !rendered.isEmpty else { return nil }
            return "\(key): \(rendered)"
        }

        return lines.isEmpty ? nil : lines.joined(separator: "\n")
    }

    private nonisolated static func renderValue(_ value: Any) -> String {
        switch value {
        case let string as String:
            return string
        case let number as NSNumber:
            return number.stringValue
        case let array as [Any]:
            return array.map(renderValue).joined(separator: ", ")
        case let dictionary as [String: Any]:
            let pairs = dictionary.keys.sorted().map { key in
                "\(key): \(renderValue(dictionary[key] as Any))"
            }
            return pairs.joined(separator: ", ")
        default:
            return ""
        }
    }

    private nonisolated static func makeRetryPrompt(
        toolName: String,
        formattedInput: String?,
        originalPrompt: String
    ) -> String {
        var sections = [
            "The user approved the pending \(toolName) tool request.",
            "Continue the previous task and execute the approved tool if it is still needed.",
            "Original user request:\n\(originalPrompt)"
        ]

        if let formattedInput, !formattedInput.isEmpty {
            sections.append("Approved tool input:\n\(formattedInput)")
        }

        return sections.joined(separator: "\n\n")
    }
}
