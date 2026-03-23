//
//  ThreadSessionRouting.swift
//  ClaudeIsland
//
//  Routing rules for how a thread should talk to Claude CLI.
//

import Foundation

enum ThreadSessionRoute: Equatable {
    case sendToActiveProcess
    case resumePersistedSession(String)
    case startNewSession
}

enum ThreadSessionRouter {
    static func route(isActiveProcess: Bool, cliSessionId: String?) -> ThreadSessionRoute {
        if isActiveProcess {
            return .sendToActiveProcess
        }

        if let sessionId = normalizeCLISessionId(cliSessionId) {
            return .resumePersistedSession(sessionId)
        }

        return .startNewSession
    }
}
