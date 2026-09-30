//
//  StreamingResponseSupport.swift
//  ClaudeIsland
//
//  Pure helpers for buffering live response chunks before publishing them to SwiftUI.
//

import Foundation

enum StreamingResponseRenderMode: Equatable, Sendable {
    case plainText
    case markdown
}

struct StreamingResponseBuffer: Equatable, Sendable {
    static let flushIntervalNanoseconds: UInt64 = 50_000_000

    private(set) var committedText = ""
    private(set) var pendingText = ""

    mutating func append(_ chunk: String) {
        guard !chunk.isEmpty else { return }
        pendingText.append(chunk)
    }

    @discardableResult
    mutating func flush() -> Bool {
        guard !pendingText.isEmpty else { return false }
        committedText.append(pendingText)
        pendingText.removeAll(keepingCapacity: true)
        return true
    }

    mutating func reset() {
        committedText.removeAll(keepingCapacity: true)
        pendingText.removeAll(keepingCapacity: true)
    }

    func resolvedText(fallback: String) -> String {
        let combinedText = committedText + pendingText
        return combinedText.isEmpty ? fallback : combinedText
    }
}

enum StreamingResponseRenderingSupport {
    static func mode(isStreaming: Bool) -> StreamingResponseRenderMode {
        isStreaming ? .plainText : .markdown
    }
}
