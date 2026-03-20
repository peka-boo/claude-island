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

    /// Parse a single line of stream-json output
    func parseLine(_ line: String) -> CLIStreamEvent? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        guard let data = trimmed.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String else {
            return nil
        }

        switch type {
        case "assistant":
            return parseAssistantEvent(json)

        case "result":
            return parseResultEvent(json)

        case "error":
            let message = json["message"] as? String ?? "Unknown error"
            return .error(message)

        default:
            return .unknown(type: type, raw: trimmed)
        }
    }

    // MARK: - Private Parsing

    private func parseAssistantEvent(_ json: [String: Any]) -> CLIStreamEvent? {
        guard let message = json["message"] as? [String: Any],
              let contentArray = message["content"] as? [[String: Any]] else {
            return nil
        }

        let sessionId = json["session_id"] as? String

        // Process content blocks
        for block in contentArray {
            guard let blockType = block["type"] as? String else { continue }

            switch blockType {
            case "thinking":
                if let thinking = block["thinking"] as? String, !thinking.isEmpty {
                    return .thinking(thinking)
                }

            case "text":
                if let text = block["text"] as? String {
                    return .text(text)
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
                return .toolUse(id: toolId, name: toolName, input: inputString)

            case "tool_result":
                let toolId = block["tool_use_id"] as? String ?? ""
                let content = block["content"] as? String ?? ""
                return .toolResult(id: toolId, name: "", output: content)

            default:
                break
            }
        }

        // If we got an assistant message with a session_id but no parsed content,
        // it might be a session start signal
        if let sid = sessionId, contentArray.isEmpty {
            return .sessionStart(sessionId: sid)
        }

        return nil
    }

    private func parseResultEvent(_ json: [String: Any]) -> CLIStreamEvent? {
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

        return .result(CLIResultInfo(
            sessionId: sessionId,
            result: result,
            isError: isError,
            costUsd: costUsd,
            tokensIn: tokensIn,
            tokensOut: tokensOut,
            durationMs: durationMs,
            stopReason: stopReason
        ))
    }
}
