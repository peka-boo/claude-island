//
//  MessageItemView.swift
//  ClaudeIsland
//
//  View that dispatches to appropriate message subview based on item type.
//

import SwiftUI

struct MessageItemView: View {
    let item: ChatHistoryItem
    let sessionId: String
    let agentDescriptions: [String: String]

    init(item: ChatHistoryItem, sessionId: String, agentDescriptions: [String: String] = [:]) {
        self.item = item
        self.sessionId = sessionId
        self.agentDescriptions = agentDescriptions
    }

    var body: some View {
        switch item.type {
        case .user(let text):
            UserMessageView(text: text)
        case .assistant(let text):
            AssistantMessageView(text: text)
        case .toolCall(let tool):
            ToolCallView(tool: tool, sessionId: sessionId, agentDescriptions: agentDescriptions)
        case .thinking(let text):
            ThinkingView(text: text)
        case .interrupted:
            InterruptedMessageView()
        }
    }
}