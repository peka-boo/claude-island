//
//  ImportedSessionHistoryParser.swift
//  ClaudeIsland
//
//  Parses Claude CLI JSONL files into importable message records for the main window.
//  Inspired by CodePilot's claude-session-parser, but tailored to the local SwiftData schema.
//

import Foundation

enum ImportedSessionMessageRole: String, Sendable {
    case user
    case assistant
    case system
}

struct ImportedSessionMessageRecord: Sendable {
    let role: ImportedSessionMessageRole
    let content: String
    let thinking: String?
    let toolName: String?
    let toolInput: String?
    let toolResult: String?
    let createdAt: Date
}

struct ImportedSessionHistory: Sendable {
    let firstMessage: String
    let messageRecords: [ImportedSessionMessageRecord]
    let createdAt: Date?
    let updatedAt: Date?
}

enum ImportedSessionHistoryParser {
    private static let fractionalFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let plainFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static func parse(jsonlURL: URL) throws -> ImportedSessionHistory {
        let rawContent = try String(contentsOf: jsonlURL, encoding: .utf8)
        let lines = rawContent.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }

        var records: [ImportedSessionMessageRecord] = []
        var firstMessage: String?
        var toolRecordIndexById: [String: Int] = [:]
        var pendingToolResults: [String: String] = [:]
        var sequence = 0

        for line in lines {
            guard let data = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let type = json["type"] as? String,
                  json["isMeta"] as? Bool != true else {
                continue
            }

            let timestamp = parseDate(json["timestamp"] as? String) ?? Date()

            switch type {
            case "user":
                if let toolResults = extractToolResults(from: json) {
                    for (toolUseId, result) in toolResults {
                        attachToolResult(
                            result,
                            to: toolUseId,
                            records: &records,
                            toolRecordIndexById: &toolRecordIndexById,
                            pendingToolResults: &pendingToolResults
                        )
                    }
                }

                guard let message = json["message"] as? [String: Any],
                      let userText = extractUserText(from: message),
                      let cleanedText = sanitizeUserFacingText(userText) else {
                    continue
                }

                if firstMessage == nil {
                    firstMessage = cleanedText
                }

                records.append(
                    ImportedSessionMessageRecord(
                        role: .user,
                        content: cleanedText,
                        thinking: nil,
                        toolName: nil,
                        toolInput: nil,
                        toolResult: nil,
                        createdAt: makeOrderedDate(base: timestamp, sequence: &sequence)
                    )
                )

            case "assistant":
                guard let message = json["message"] as? [String: Any] else { continue }

                let parsedAssistant = parseAssistantMessage(message)

                if parsedAssistant.hasRenderableContent {
                    records.append(
                        ImportedSessionMessageRecord(
                            role: .assistant,
                            content: parsedAssistant.text,
                            thinking: parsedAssistant.thinking,
                            toolName: nil,
                            toolInput: nil,
                            toolResult: nil,
                            createdAt: makeOrderedDate(base: timestamp, sequence: &sequence)
                        )
                    )
                }

                for toolUse in parsedAssistant.toolUses {
                    let attachedResult = pendingToolResults.removeValue(forKey: toolUse.id)
                    records.append(
                        ImportedSessionMessageRecord(
                            role: .assistant,
                            content: "",
                            thinking: nil,
                            toolName: toolUse.name,
                            toolInput: serializeJSON(toolUse.input),
                            toolResult: attachedResult,
                            createdAt: makeOrderedDate(base: timestamp, sequence: &sequence)
                        )
                    )
                    toolRecordIndexById[toolUse.id] = records.count - 1
                }

                for inlineResult in parsedAssistant.inlineToolResults {
                    attachToolResult(
                        inlineResult.result,
                        to: inlineResult.toolUseId,
                        records: &records,
                        toolRecordIndexById: &toolRecordIndexById,
                        pendingToolResults: &pendingToolResults
                    )
                }

            default:
                continue
            }
        }

        let createdAt = records.first?.createdAt
        let updatedAt = records.last?.createdAt

        return ImportedSessionHistory(
            firstMessage: firstMessage ?? "No messages",
            messageRecords: records,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    private static func parseDate(_ value: String?) -> Date? {
        guard let value else { return nil }
        return fractionalFormatter.date(from: value) ?? plainFormatter.date(from: value)
    }

    private static func makeOrderedDate(base: Date, sequence: inout Int) -> Date {
        defer { sequence += 1 }
        return base.addingTimeInterval(Double(sequence) * 0.001)
    }

    private static func extractUserText(from message: [String: Any]) -> String? {
        if let content = message["content"] as? String {
            return content
        }

        guard let blocks = message["content"] as? [[String: Any]] else {
            return nil
        }

        let text = blocks.compactMap { block -> String? in
            guard block["type"] as? String == "text" else { return nil }
            return block["text"] as? String
        }
        .joined(separator: "\n")

        return text.isEmpty ? nil : text
    }

    private struct ParsedAssistantMessage {
        struct ToolUse {
            let id: String
            let name: String
            let input: Any
        }

        struct InlineToolResult {
            let toolUseId: String
            let result: String
        }

        let text: String
        let thinking: String?
        let toolUses: [ToolUse]
        let inlineToolResults: [InlineToolResult]

        var hasRenderableContent: Bool {
            !text.isEmpty || !(thinking?.isEmpty ?? true)
        }
    }

    private static func parseAssistantMessage(_ message: [String: Any]) -> ParsedAssistantMessage {
        if let content = message["content"] as? String {
            let cleaned = sanitizeUserFacingText(content) ?? ""
            return ParsedAssistantMessage(
                text: cleaned,
                thinking: nil,
                toolUses: [],
                inlineToolResults: []
            )
        }

        guard let blocks = message["content"] as? [[String: Any]] else {
            return ParsedAssistantMessage(text: "", thinking: nil, toolUses: [], inlineToolResults: [])
        }

        var textBlocks: [String] = []
        var thinkingBlocks: [String] = []
        var toolUses: [ParsedAssistantMessage.ToolUse] = []
        var inlineToolResults: [ParsedAssistantMessage.InlineToolResult] = []

        for block in blocks {
            switch block["type"] as? String {
            case "text":
                if let text = block["text"] as? String,
                   let cleaned = sanitizeUserFacingText(text) {
                    textBlocks.append(cleaned)
                }

            case "thinking":
                if let thinking = block["thinking"] as? String,
                   !thinking.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    thinkingBlocks.append(thinking)
                }

            case "tool_use":
                guard let id = block["id"] as? String,
                      let name = block["name"] as? String else { continue }
                toolUses.append(.init(id: id, name: name, input: block["input"] ?? [:]))

            case "tool_result":
                if let toolUseId = block["tool_use_id"] as? String,
                   let result = renderToolResult(blockContent: block["content"], fallback: nil) {
                    inlineToolResults.append(.init(toolUseId: toolUseId, result: result))
                }

            default:
                continue
            }
        }

        return ParsedAssistantMessage(
            text: textBlocks.joined(separator: "\n\n"),
            thinking: thinkingBlocks.isEmpty ? nil : thinkingBlocks.joined(separator: "\n\n"),
            toolUses: toolUses,
            inlineToolResults: inlineToolResults
        )
    }

    private static func extractToolResults(from json: [String: Any]) -> [(String, String)]? {
        guard let message = json["message"] as? [String: Any],
              let blocks = message["content"] as? [[String: Any]] else {
            return nil
        }

        let toolUseResult = json["toolUseResult"] as? [String: Any]
        let fallback = renderToolResult(
            blockContent: nil,
            fallback: toolUseResult
        )

        let extracted = blocks.compactMap { block -> (String, String)? in
            guard block["type"] as? String == "tool_result",
                  let toolUseId = block["tool_use_id"] as? String else {
                return nil
            }

            let rendered = renderToolResult(
                blockContent: block["content"],
                fallback: toolUseResult
            ) ?? fallback

            guard let rendered, !rendered.isEmpty else { return nil }
            return (toolUseId, rendered)
        }

        return extracted.isEmpty ? nil : extracted
    }

    private static func renderToolResult(blockContent: Any?, fallback: [String: Any]?) -> String? {
        var parts: [String] = []

        if let blockContent = blockContent {
            if let text = blockContent as? String,
               !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                parts.append(text)
            } else if let blocks = blockContent as? [[String: Any]] {
                let combined = blocks.compactMap { block -> String? in
                    guard block["type"] as? String == "text" else { return nil }
                    return block["text"] as? String
                }
                .joined(separator: "\n")

                if !combined.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    parts.append(combined)
                }
            }
        }

        if let fallback {
            if let content = fallback["content"] as? String,
               !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               !parts.contains(content) {
                parts.append(content)
            }
            if let result = fallback["result"] as? String,
               !result.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               !parts.contains(result) {
                parts.append(result)
            }
            if let stdout = fallback["stdout"] as? String,
               !stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               !parts.contains(stdout) {
                parts.append(stdout)
            }
            if let stderr = fallback["stderr"] as? String,
               !stderr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               !parts.contains(stderr) {
                parts.append(stderr)
            }
        }

        let merged = parts.joined(separator: "\n\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return merged.isEmpty ? nil : merged
    }

    private static func attachToolResult(
        _ result: String,
        to toolUseId: String,
        records: inout [ImportedSessionMessageRecord],
        toolRecordIndexById: inout [String: Int],
        pendingToolResults: inout [String: String]
    ) {
        if let index = toolRecordIndexById[toolUseId], records.indices.contains(index) {
            let existing = records[index]
            let mergedResult = mergeToolResult(existing.toolResult, result)
            records[index] = ImportedSessionMessageRecord(
                role: existing.role,
                content: existing.content,
                thinking: existing.thinking,
                toolName: existing.toolName,
                toolInput: existing.toolInput,
                toolResult: mergedResult,
                createdAt: existing.createdAt
            )
        } else {
            pendingToolResults[toolUseId] = mergeToolResult(pendingToolResults[toolUseId], result)
        }
    }

    private static func mergeToolResult(_ lhs: String?, _ rhs: String?) -> String? {
        let parts = [lhs, rhs]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !parts.isEmpty else { return nil }
        return Array(NSOrderedSet(array: parts)).compactMap { $0 as? String }.joined(separator: "\n\n")
    }

    private static func sanitizeUserFacingText(_ text: String) -> String? {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty,
              !cleaned.hasPrefix("<command-name>"),
              !cleaned.hasPrefix("<local-command"),
              !cleaned.hasPrefix("Caveat:"),
              !cleaned.hasPrefix("[Request interrupted by user") else {
            return nil
        }
        return cleaned
    }

    private static func serializeJSON(_ value: Any) -> String? {
        guard JSONSerialization.isValidJSONObject(value),
              let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]),
              let string = String(data: data, encoding: .utf8) else {
            if let string = value as? String {
                return string
            }
            return nil
        }
        return string
    }
}
