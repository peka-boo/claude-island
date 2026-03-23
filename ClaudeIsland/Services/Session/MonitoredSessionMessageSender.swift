//
//  MonitoredSessionMessageSender.swift
//  ClaudeIsland
//
//  Sends follow-up messages back to live monitored Claude sessions.
//

import Foundation

actor MonitoredSessionMessageSender {
    static let shared = MonitoredSessionMessageSender()

    private var syncTasks: [String: Task<Void, Never>] = [:]

    func sendMessage(_ message: String, to session: SessionState) async -> Bool {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        switch SessionMessageTransportSupport.transport(
            isInTmux: session.isInTmux,
            tty: session.tty,
            sessionId: session.sessionId,
            allowsDetachedResume: true
        ) {
        case .tmux(let tty):
            guard let target = await TmuxController.shared.findTmuxTarget(forTTY: tty) else {
                return false
            }
            return await TmuxController.shared.sendMessage(trimmed, to: target)

        case .detachedResume(let sessionId):
            let didSend = await CLISessionManager.shared.sendDetachedTurn(
                sessionId: sessionId,
                cwd: session.cwd,
                prompt: trimmed
            )
            guard didSend,
                  let threadId = SessionMessageTransportSupport.detachedThreadId(for: sessionId) else {
                return false
            }

            startDetachedHistorySync(
                threadId: threadId,
                sessionId: session.sessionId,
                cwd: session.cwd
            )
            return true

        case .unavailable:
            return false
        }
    }

    private func startDetachedHistorySync(
        threadId: String,
        sessionId: String,
        cwd: String
    ) {
        syncTasks[threadId]?.cancel()

        syncTasks[threadId] = Task { [weak self] in
            defer {
                Task { await self?.clearSyncTask(for: threadId) }
            }

            await SessionStore.shared.process(.loadHistory(sessionId: sessionId, cwd: cwd))

            while await CLISessionManager.shared.isActive(threadId: threadId) {
                try? await Task.sleep(nanoseconds: 700_000_000)
                guard !Task.isCancelled else { return }
                await SessionStore.shared.process(.loadHistory(sessionId: sessionId, cwd: cwd))
            }

            guard !Task.isCancelled else { return }
            await SessionStore.shared.process(.loadHistory(sessionId: sessionId, cwd: cwd))
        }
    }

    private func clearSyncTask(for threadId: String) {
        syncTasks.removeValue(forKey: threadId)
    }
}
