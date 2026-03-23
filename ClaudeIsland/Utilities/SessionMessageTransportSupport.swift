//
//  SessionMessageTransportSupport.swift
//  ClaudeIsland
//
//  Routing helpers for sending messages back to monitored Claude sessions.
//

import Foundation

enum SessionMessageTransport: Equatable, Sendable {
    case tmux(tty: String)
    case detachedResume(sessionId: String)
    case unavailable
}

enum SessionMessageTransportSupport {
    nonisolated static func transport(
        isInTmux: Bool,
        tty: String?,
        sessionId: String?,
        allowsDetachedResume: Bool
    ) -> SessionMessageTransport {
        if isInTmux,
           let tty = normalizedTTY(tty) {
            return .tmux(tty: tty)
        }

        if allowsDetachedResume,
           let sessionId = normalizeCLISessionId(sessionId) {
            return .detachedResume(sessionId: sessionId)
        }

        return .unavailable
    }

    nonisolated static func detachedThreadId(for sessionId: String?) -> String? {
        guard let normalizedSessionId = normalizeCLISessionId(sessionId) else {
            return nil
        }

        return "detached-session:\(normalizedSessionId)"
    }

    nonisolated static func placeholder(for transport: SessionMessageTransport) -> String {
        switch transport {
        case .tmux, .detachedResume:
            return "Message Claude..."
        case .unavailable:
            return "Messaging unavailable for this session"
        }
    }

    nonisolated static func canSendMessages(
        isInTmux: Bool,
        tty: String?,
        sessionId: String?,
        allowsDetachedResume: Bool
    ) -> Bool {
        switch transport(
            isInTmux: isInTmux,
            tty: tty,
            sessionId: sessionId,
            allowsDetachedResume: allowsDetachedResume
        ) {
        case .tmux, .detachedResume:
            return true
        case .unavailable:
            return false
        }
    }

    nonisolated private static func normalizedTTY(_ rawTTY: String?) -> String? {
        guard let rawTTY else { return nil }

        let trimmed = rawTTY.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return trimmed
    }
}
