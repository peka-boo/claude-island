//
//  StructuredHistorySnapshotBuilder.swift
//  ClaudeIsland
//
//  Builds a structured history snapshot for main-window rendering from Claude JSONL files.
//

import Foundation

struct StructuredHistorySnapshot: Sendable {
    let items: [ChatHistoryItem]
    let agentDescriptions: [String: String]

    static let empty = StructuredHistorySnapshot(items: [], agentDescriptions: [:])
}

enum StructuredHistorySnapshotBuilder {
    static func load(sessionId: String, cwd: String) async -> StructuredHistorySnapshot {
        let messages = await ConversationParser.shared.parseFullConversation(
            sessionId: sessionId,
            cwd: cwd
        )
        let completedTools = await ConversationParser.shared.completedToolIds(for: sessionId)
        let toolResults = await ConversationParser.shared.toolResults(for: sessionId)
        let structuredResults = await ConversationParser.shared.structuredResults(for: sessionId)

        var items: [ChatHistoryItem] = []
        var existingIds = Set<String>()
        var seenToolIds = Set<String>()

        for message in messages {
            for (blockIndex, block) in message.content.enumerated() {
                guard let item = createChatItem(
                    from: block,
                    message: message,
                    blockIndex: blockIndex,
                    existingIds: &existingIds,
                    seenToolIds: &seenToolIds,
                    completedTools: completedTools,
                    toolResults: toolResults,
                    structuredResults: structuredResults
                ) else {
                    continue
                }

                items.append(item)
            }
        }

        var agentDescriptions: [String: String] = [:]
        await attachSubagentTools(
            to: &items,
            cwd: cwd,
            agentDescriptions: &agentDescriptions
        )

        items.sort { $0.timestamp < $1.timestamp }
        return StructuredHistorySnapshot(items: items, agentDescriptions: agentDescriptions)
    }

    private static func createChatItem(
        from block: MessageBlock,
        message: ChatMessage,
        blockIndex: Int,
        existingIds: inout Set<String>,
        seenToolIds: inout Set<String>,
        completedTools: Set<String>,
        toolResults: [String: ConversationParser.ToolResult],
        structuredResults: [String: ToolResultData]
    ) -> ChatHistoryItem? {
        switch block {
        case .text(let text):
            let itemId = "\(message.id)-text-\(blockIndex)"
            guard existingIds.insert(itemId).inserted else { return nil }

            if message.role == .user {
                return ChatHistoryItem(id: itemId, type: .user(text), timestamp: message.timestamp)
            } else {
                return ChatHistoryItem(id: itemId, type: .assistant(text), timestamp: message.timestamp)
            }

        case .thinking(let text):
            let itemId = "\(message.id)-thinking-\(blockIndex)"
            guard existingIds.insert(itemId).inserted else { return nil }
            return ChatHistoryItem(id: itemId, type: .thinking(text), timestamp: message.timestamp)

        case .interrupted:
            let itemId = "\(message.id)-interrupted-\(blockIndex)"
            guard existingIds.insert(itemId).inserted else { return nil }
            return ChatHistoryItem(id: itemId, type: .interrupted, timestamp: message.timestamp)

        case .toolUse(let tool):
            guard seenToolIds.insert(tool.id).inserted else { return nil }

            let isCompleted = completedTools.contains(tool.id)
            let parserResult = toolResults[tool.id]
            let structuredResult = structuredResults[tool.id]
            let status = isCompleted
                ? resolvedToolStatus(from: parserResult)
                : ToolStatus.running

            return ChatHistoryItem(
                id: tool.id,
                type: .toolCall(
                    ToolCallItem(
                        name: tool.name,
                        input: tool.input,
                        status: status,
                        result: isCompleted ? resolvedToolResultText(from: parserResult) : nil,
                        structuredResult: structuredResult,
                        subagentTools: []
                    )
                ),
                timestamp: message.timestamp
            )
        }
    }

    private static func resolvedToolStatus(from parserResult: ConversationParser.ToolResult?) -> ToolStatus {
        if parserResult?.isInterrupted == true {
            return .interrupted
        }
        if parserResult?.isError == true {
            return .error
        }
        return .success
    }

    private static func resolvedToolResultText(from parserResult: ConversationParser.ToolResult?) -> String? {
        guard let parserResult, !parserResult.isInterrupted else { return nil }

        if let stdout = parserResult.stdout, !stdout.isEmpty {
            return stdout
        }
        if let stderr = parserResult.stderr, !stderr.isEmpty {
            return stderr
        }
        if let content = parserResult.content, !content.isEmpty {
            return content
        }
        return nil
    }

    private static func attachSubagentTools(
        to items: inout [ChatHistoryItem],
        cwd: String,
        agentDescriptions: inout [String: String]
    ) async {
        for index in items.indices {
            guard case .toolCall(var tool) = items[index].type,
                  case .task(let taskResult)? = tool.structuredResult,
                  !taskResult.agentId.isEmpty else {
                continue
            }

            if let description = tool.input["description"] ?? taskResult.prompt,
               !description.isEmpty {
                agentDescriptions[taskResult.agentId] = description
            }

            let subagentTools = await ConversationParser.shared.parseSubagentTools(
                agentId: taskResult.agentId,
                cwd: cwd
            )

            guard !subagentTools.isEmpty else { continue }

            tool.subagentTools = subagentTools.map { info in
                SubagentToolCall(
                    id: info.id,
                    name: info.name,
                    input: info.input,
                    status: info.isCompleted ? .success : .running,
                    timestamp: parseTimestamp(info.timestamp) ?? items[index].timestamp
                )
            }

            items[index] = ChatHistoryItem(
                id: items[index].id,
                type: .toolCall(tool),
                timestamp: items[index].timestamp
            )
        }
    }

    private static func parseTimestamp(_ timestamp: String?) -> Date? {
        guard let timestamp else { return nil }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: timestamp)
    }
}
