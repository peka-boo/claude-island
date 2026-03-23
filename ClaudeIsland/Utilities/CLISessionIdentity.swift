//
//  CLISessionIdentity.swift
//  ClaudeIsland
//
//  Helpers for working with Claude CLI session identifiers.
//

import Foundation

nonisolated func normalizeCLISessionId(_ rawValue: String?) -> String? {
    guard let rawValue else { return nil }

    let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }

    if trimmed.hasSuffix(".jsonl") {
        return String(trimmed.dropLast(".jsonl".count))
    }

    return trimmed
}
