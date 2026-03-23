//
//  GlobalSessionSupport.swift
//  ClaudeIsland
//
//  Shared helpers for building the Global Monitor list from live and scanned sessions.
//

import Foundation

enum GlobalSessionSource: String, Sendable {
    case live
    case history
}

enum SidebarSessionIdentity: Hashable, Equatable, Sendable {
    case cliSession(String)
    case thread(String)

    var selectionKey: String {
        switch self {
        case .cliSession(let sessionId):
            return "cli:\(sessionId)"
        case .thread(let threadId):
            return "thread:\(threadId)"
        }
    }
}

enum SidebarSessionStatus: String, Equatable, Sendable {
    case processing
    case waitingForInput
    case waitingForApproval
    case compacting
    case active
    case idle
    case ended

    var showsActivityBadge: Bool {
        switch self {
        case .processing, .waitingForApproval, .compacting:
            return true
        case .waitingForInput, .active, .idle, .ended:
            return false
        }
    }

    var activityLabel: String? {
        switch self {
        case .processing:
            return "Active"
        case .waitingForApproval:
            return "Approval"
        case .compacting:
            return "Compacting"
        case .waitingForInput, .active, .idle, .ended:
            return nil
        }
    }
}

struct GlobalSessionGroup: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let path: String
    let sessions: [HookSessionInfo]
}

enum GlobalSessionOpenAction: Equatable {
    case openExistingThread(String)
    case createTakeoverThread
}

struct HookSessionInfo: Identifiable, Equatable, Sendable {
    let id: String
    let sessionId: String
    let projectPath: String
    let projectName: String
    let title: String?
    let gitBranch: String?
    let status: String
    let startedAt: Date
    var lastEventAt: Date
    var messageCount: Int
    let source: GlobalSessionSource

    var isLive: Bool {
        source == .live
    }
}

enum GlobalSessionSupport {
    nonisolated static func selectionIdentity(threadId: String, cliSessionId: String?) -> SidebarSessionIdentity {
        if let normalizedSessionId = normalizeCLISessionId(cliSessionId) {
            return .cliSession(normalizedSessionId)
        }

        return .thread(threadId)
    }

    nonisolated static func selectionIdentity(sessionId: String) -> SidebarSessionIdentity {
        .cliSession(normalizeCLISessionId(sessionId) ?? sessionId)
    }

    nonisolated static func resolvedStatus(threadStatus: String, sessionStatus: String?) -> SidebarSessionStatus {
        if let sessionStatus {
            return sidebarStatus(from: sessionStatus)
        }

        return sidebarStatus(from: threadStatus)
    }

    nonisolated static func resolvedLastEventAt(threadUpdatedAt: Date, sessionLastEventAt: Date?) -> Date {
        sessionLastEventAt ?? threadUpdatedAt
    }

    nonisolated static func historySession(from session: ImportableSession) -> HookSessionInfo {
        HookSessionInfo(
            id: session.id,
            sessionId: session.id,
            projectPath: session.projectPath,
            projectName: session.projectName,
            title: session.firstMessage == "No messages" ? nil : session.firstMessage,
            gitBranch: session.gitBranch,
            status: "ended",
            startedAt: session.lastModified,
            lastEventAt: session.lastModified,
            messageCount: session.messageCount,
            source: .history
        )
    }

    nonisolated static func mergedSessions(
        live: [HookSessionInfo],
        scanned: [ImportableSession],
        searchText: String
    ) -> [HookSessionInfo] {
        var merged: [String: HookSessionInfo] = [:]

        for session in scanned {
            let historySession = historySession(from: session)
            let key = normalizeCLISessionId(historySession.sessionId) ?? historySession.sessionId
            merged[key] = historySession
        }

        for session in live {
            let key = normalizeCLISessionId(session.sessionId) ?? session.sessionId
            merged[key] = session
        }

        let normalizedSearch = searchText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        return merged.values
            .filter { session in
                matchesSearch(session: session, normalizedSearch: normalizedSearch)
            }
            .sorted(by: sortPredicate(lhs:rhs:))
    }

    nonisolated static func groupedSessions(_ sessions: [HookSessionInfo]) -> [GlobalSessionGroup] {
        let grouped = Dictionary(grouping: sessions) { session in
            session.projectPath
        }

        return grouped.compactMap { projectPath, sessions in
            guard let firstSession = sessions.first else { return nil }
            let sortedSessions = sessions.sorted(by: sortPredicate(lhs:rhs:))
            return GlobalSessionGroup(
                id: projectPath,
                name: firstSession.projectName,
                path: projectPath,
                sessions: sortedSessions
            )
        }
        .sorted { lhs, rhs in
            let lhsDate = lhs.sessions.first?.lastEventAt ?? .distantPast
            let rhsDate = rhs.sessions.first?.lastEventAt ?? .distantPast
            if lhsDate != rhsDate {
                return lhsDate > rhsDate
            }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    nonisolated static func openAction(existingThreadId: String?) -> GlobalSessionOpenAction {
        if let existingThreadId, !existingThreadId.isEmpty {
            return .openExistingThread(existingThreadId)
        }

        return .createTakeoverThread
    }

    nonisolated private static func matchesSearch(session: HookSessionInfo, normalizedSearch: String) -> Bool {
        guard !normalizedSearch.isEmpty else { return true }

        return session.projectName.lowercased().contains(normalizedSearch) ||
            session.projectPath.lowercased().contains(normalizedSearch) ||
            (session.title?.lowercased().contains(normalizedSearch) ?? false) ||
            (session.gitBranch?.lowercased().contains(normalizedSearch) ?? false) ||
            session.status.lowercased().contains(normalizedSearch)
    }

    nonisolated private static func sortPredicate(lhs: HookSessionInfo, rhs: HookSessionInfo) -> Bool {
        if lhs.lastEventAt != rhs.lastEventAt {
            return lhs.lastEventAt > rhs.lastEventAt
        }

        if lhs.source != rhs.source {
            return lhs.source == .live
        }

        return lhs.projectName.localizedCaseInsensitiveCompare(rhs.projectName) == .orderedAscending
    }

    nonisolated private static func sidebarStatus(from rawStatus: String) -> SidebarSessionStatus {
        switch rawStatus.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "processing":
            return .processing
        case "waitingforinput":
            return .waitingForInput
        case "waitingforapproval":
            return .waitingForApproval
        case "compacting":
            return .compacting
        case "active":
            return .active
        case "ended":
            return .ended
        case "idle":
            return .idle
        default:
            return .idle
        }
    }
}
