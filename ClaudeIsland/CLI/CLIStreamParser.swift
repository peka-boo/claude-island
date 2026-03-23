//
//  CLIStreamParser.swift
//  ClaudeIsland
//
//  Parses Claude CLI `--output-format stream-json` output line by line.
//  Each line is a JSON object representing an event in the conversation.
//

import Foundation

// MARK: - Stream Events

/// Events emitted by parsing Claude CLI stream-json output
enum CLIStreamEvent: Sendable {
    /// Claude is thinking/reasoning
    case thinking(String)

    /// Claude produced text output
    case text(String)

    /// Claude is using a tool
    case toolUse(id: String, name: String, input: String)

    /// Tool execution result
    case toolResult(id: String, name: String, output: String)

    /// Session started (initial message)
    case sessionStart(sessionId: String)

    /// Conversation turn completed successfully
    case result(CLIResultInfo)

    /// An error occurred
    case error(String)

    /// Raw/unknown event for forward compatibility
    case unknown(type: String, raw: String)
}

/// Information from a completed result event
struct CLIResultInfo: Sendable {
    let sessionId: String
    let result: String
    let isError: Bool
    let costUsd: Double
    let tokensIn: Int
    let tokensOut: Int
    let durationMs: Int
    let stopReason: String
}

// MARK: - Parser

/// Parses newline-delimited JSON from Claude CLI stdout.
///
/// Usage:
/// ```swift
/// let parser = CLIStreamParser()
/// for try await line in process.stdout.lines {
///     if let event = parser.parseLine(line) {
///         // handle event
///     }
/// }
/// ```
struct CLIStreamParser: Sendable {
    nonisolated init() {}

    /// Parse a single line of stream-json output
    nonisolated func parseLine(_ line: String) -> [CLIStreamEvent] {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        guard let data = trimmed.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String else {
            return []
        }

        switch type {
        case "assistant":
            return parseAssistantEvent(json)

        case "user":
            return parseUserEvent(json)

        case "system":
            return parseSystemEvent(json)

        case "result":
            return parseResultEvent(json)

        case "error":
            let message = json["message"] as? String ?? "Unknown error"
            return [.error(message)]

        default:
            return [.unknown(type: type, raw: trimmed)]
        }
    }

    // MARK: - Private Parsing

    private nonisolated func parseAssistantEvent(_ json: [String: Any]) -> [CLIStreamEvent] {
        guard let message = json["message"] as? [String: Any],
              let contentArray = message["content"] as? [[String: Any]] else {
            return []
        }

        let sessionId = json["session_id"] as? String
        var events: [CLIStreamEvent] = []

        // Process content blocks
        for block in contentArray {
            guard let blockType = block["type"] as? String else { continue }

            switch blockType {
            case "thinking":
                if let thinking = block["thinking"] as? String, !thinking.isEmpty {
                    events.append(.thinking(thinking))
                }

            case "text":
                if let text = block["text"] as? String {
                    events.append(.text(text))
                }

            case "tool_use":
                let toolId = block["id"] as? String ?? ""
                let toolName = block["name"] as? String ?? "unknown"
                let inputData = block["input"] as? [String: Any] ?? [:]
                let inputString: String
                if let jsonData = try? JSONSerialization.data(withJSONObject: inputData),
                   let str = String(data: jsonData, encoding: .utf8) {
                    inputString = str
                } else {
                    inputString = "{}"
                }
                events.append(.toolUse(id: toolId, name: toolName, input: inputString))

            case "tool_result":
                let toolId = block["tool_use_id"] as? String ?? ""
                let content = parseToolResultContent(block["content"])
                events.append(.toolResult(id: toolId, name: "", output: content))

            default:
                break
            }
        }

        if let sid = sessionId, events.isEmpty, contentArray.isEmpty {
            events.append(.sessionStart(sessionId: sid))
        }

        return events
    }

    private nonisolated func parseUserEvent(_ json: [String: Any]) -> [CLIStreamEvent] {
        guard let message = json["message"] as? [String: Any],
              let contentArray = message["content"] as? [[String: Any]] else {
            return []
        }

        var events: [CLIStreamEvent] = []

        for block in contentArray {
            guard let blockType = block["type"] as? String else { continue }

            switch blockType {
            case "tool_result":
                let toolId = block["tool_use_id"] as? String ?? ""
                let content = parseToolResultContent(block["content"])
                events.append(.toolResult(id: toolId, name: "", output: content))

            case "text":
                if let text = block["text"] as? String {
                    events.append(.text(text))
                }

            default:
                break
            }
        }

        return events
    }

    private nonisolated func parseSystemEvent(_ json: [String: Any]) -> [CLIStreamEvent] {
        let subtype = json["subtype"] as? String ?? ""

        switch subtype {
        case "init":
            guard let sessionId = json["session_id"] as? String, !sessionId.isEmpty else {
                return []
            }
            return [.sessionStart(sessionId: sessionId)]

        default:
            return []
        }
    }

    private nonisolated func parseResultEvent(_ json: [String: Any]) -> [CLIStreamEvent] {
        let sessionId = json["session_id"] as? String ?? ""
        let result = json["result"] as? String ?? ""
        let isError = json["is_error"] as? Bool ?? false
        let costUsd = json["total_cost_usd"] as? Double ?? 0
        let durationMs = json["duration_ms"] as? Int ?? 0
        let stopReason = json["stop_reason"] as? String ?? ""

        // Parse usage
        var tokensIn = 0
        var tokensOut = 0
        if let usage = json["usage"] as? [String: Any] {
            tokensIn = usage["input_tokens"] as? Int ?? 0
            tokensOut = usage["output_tokens"] as? Int ?? 0
        }

        return [
            .result(CLIResultInfo(
                sessionId: sessionId,
                result: result,
                isError: isError,
                costUsd: costUsd,
                tokensIn: tokensIn,
                tokensOut: tokensOut,
                durationMs: durationMs,
                stopReason: stopReason
            ))
        ]
    }

    private nonisolated func parseToolResultContent(_ rawContent: Any?) -> String {
        if let text = rawContent as? String {
            return text
        }

        if let blocks = rawContent as? [[String: Any]] {
            let textParts = blocks.compactMap { block -> String? in
                switch block["type"] as? String {
                case "text":
                    return block["text"] as? String
                default:
                    return nil
                }
            }
            return textParts.joined(separator: "\n")
        }

        return ""
    }
}
