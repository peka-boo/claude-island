//
//  StructuredHistorySnapshotBuilder.swift
//  ClaudeIsland
//
//  Builds a structured history snapshot for main-window rendering from Claude JSONL files.
//

import Foundation
import os.log

private let snapshotLogger = Logger(subsystem: "com.claudeisland", category: "SnapshotBuilder")

struct StructuredHistorySnapshot: Sendable {
    let items: [ChatHistoryItem]
    let agentDescriptions: [String: String]

    static let empty = StructuredHistorySnapshot(items: [], agentDescriptions: [:])
}

enum StructuredHistorySnapshotBuilder {
    /// Load history snapshot in two phases for better perceived performance:
    /// 1. First returns recent messages quickly
    /// 2. Then continues loading older messages in background
    static func load(sessionId: String, cwd: String) async -> StructuredHistorySnapshot {
        snapshotLogger.info("[SNAPSHOT] ====== START load for sessionId: \(sessionId), cwd: \(cwd) ======")
        let startTime = Date()

        // Use parseIncremental which returns all data in one call
        snapshotLogger.info("[SNAPSHOT] Step 1: Calling parseIncremental...")
        let parseStartTime = Date()
        let parseResult = await ConversationParser.shared.parseIncremental(
            sessionId: sessionId,
            cwd: cwd
        )
        snapshotLogger.info("[SNAPSHOT] Step 1 DONE: parseIncremental took \(Date().timeIntervalSince(parseStartTime))s, messages: \(parseResult.allMessages.count)")

        let messages = parseResult.allMessages
        let completedTools = parseResult.completedToolIds
        let toolResults = parseResult.toolResults
        let structuredResults = parseResult.structuredResults

        snapshotLogger.info("[SNAPSHOT] Step 2: Creating chat items...")
        let createStartTime = Date()
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
        snapshotLogger.info("[SNAPSHOT] Step 2 DONE: Created \(items.count) items in \(Date().timeIntervalSince(createStartTime))s")

        snapshotLogger.info("[SNAPSHOT] Step 3: Attaching subagent tools...")
        let subagentStartTime = Date()
        var agentDescriptions: [String: String] = [:]
        await attachSubagentTools(
            to: &items,
            cwd: cwd,
            agentDescriptions: &agentDescriptions
        )
        snapshotLogger.info("[SNAPSHOT] Step 3 DONE: Subagent tools attached in \(Date().timeIntervalSince(subagentStartTime))s")

        snapshotLogger.info("[SNAPSHOT] Step 4: Sorting items...")
        items.sort { $0.timestamp < $1.timestamp }

        let totalTime = Date().timeIntervalSince(startTime)
        snapshotLogger.info("[SNAPSHOT] ====== END load: \(items.count) items, total time: \(totalTime)s ======")

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
        let itemsCount = items.count
        snapshotLogger.info("[SUBAGENT] Starting attachSubagentTools, items count: \(itemsCount)")

        // Collect all agent IDs first
        var agentIds: [(index: Int, agentId: String, description: String?, prompt: String?)] = []

        for index in items.indices {
            guard case .toolCall(let tool) = items[index].type,
                  case .task(let taskResult)? = tool.structuredResult,
                  !taskResult.agentId.isEmpty else {
                continue
            }

            snapshotLogger.info("[SUBAGENT] Found agent at index \(index), agentId: \(taskResult.agentId)")
            agentIds.append((
                index: index,
                agentId: taskResult.agentId,
                description: tool.input["description"],
                prompt: taskResult.prompt
            ))
        }

        // Early return if no agents to process
        guard !agentIds.isEmpty else {
            snapshotLogger.info("[SUBAGENT] No agents found, returning early")
            return
        }

        let agentCount = agentIds.count
        snapshotLogger.info("[SUBAGENT] Loading \(agentCount) agents in parallel...")

        // Load all subagent tools in parallel
        let loadStartTime = Date()
        let subagentToolResults = await withTaskGroup(of: (Int, [SubagentToolInfo]).self) { group in
            for (index, agentId, _, _) in agentIds {
                group.addTask {
                    snapshotLogger.info("[SUBAGENT] Starting load for agent: \(agentId)")
                    let taskStart = Date()
                    let tools = await ConversationParser.shared.parseSubagentTools(
                        agentId: agentId,
                        cwd: cwd
                    )
                    let elapsed = Date().timeIntervalSince(taskStart)
                    snapshotLogger.info("[SUBAGENT] Loaded \(tools.count) tools for agent \(agentId) in \(elapsed)s")
                    return (index, tools)
                }
            }

            var results: [Int: [SubagentToolInfo]] = [:]
            for await (index, tools) in group {
                results[index] = tools
            }
            return results
        }
        let loadElapsed = Date().timeIntervalSince(loadStartTime)
        snapshotLogger.info("[SUBAGENT] All agents loaded in \(loadElapsed)s")

        // Apply results to items
        for (index, agentId, description, prompt) in agentIds {
            // Update agent description
            if let desc = description ?? prompt, !desc.isEmpty {
                agentDescriptions[agentId] = desc
            }

            // Apply subagent tools if available
            guard let subagentTools = subagentToolResults[index], !subagentTools.isEmpty else {
                continue
            }

            guard case .toolCall(var tool) = items[index].type else { continue }

            let itemTimestamp = items[index].timestamp
            tool.subagentTools = subagentTools.map { info in
                SubagentToolCall(
                    id: info.id,
                    name: info.name,
                    input: info.input,
                    status: info.isCompleted ? .success : .running,
                    timestamp: parseTimestamp(info.timestamp) ?? itemTimestamp
                )
            }

            let itemId = items[index].id
            items[index] = ChatHistoryItem(
                id: itemId,
                type: .toolCall(tool),
                timestamp: itemTimestamp
            )
        }

        snapshotLogger.info("[SUBAGENT] Finished attachSubagentTools")
    }

    private static func parseTimestamp(_ timestamp: String?) -> Date? {
        guard let timestamp else { return nil }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: timestamp)
    }
}
