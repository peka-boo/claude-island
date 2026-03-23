//
//  ComposerProcessingSupport.swift
//  ClaudeIsland
//
//  Pure helpers for describing the chat composer processing state.
//

import Foundation

struct ComposerProcessingDescriptor: Equatable, Sendable {
    let title: String
    let detail: String
}

enum ComposerProcessingSupport {
    nonisolated static func descriptor(
        isProcessing: Bool,
        streamingText: String,
        thinkingText: String
    ) -> ComposerProcessingDescriptor? {
        guard isProcessing else { return nil }

        let normalizedStreaming = streamingText.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedThinking = thinkingText.trimmingCharacters(in: .whitespacesAndNewlines)

        if !normalizedStreaming.isEmpty {
            return ComposerProcessingDescriptor(
                title: "Claude is responding",
                detail: "Streaming the latest reply. You can interrupt or terminate at any time."
            )
        }

        if !normalizedThinking.isEmpty {
            return ComposerProcessingDescriptor(
                title: "Claude is thinking",
                detail: "Reviewing context, checking tools, and preparing the next step."
            )
        }

        return ComposerProcessingDescriptor(
            title: "Claude is thinking",
            detail: "Reviewing context, checking tools, and preparing the next step."
        )
    }
}
