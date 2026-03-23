//
//  ImportSessionFilterSupport.swift
//  ClaudeIsland
//
//  Pure filtering helpers for the Import Claude Sessions modal.
//

import Foundation

struct ImportSessionProjectFilter: Identifiable, Equatable, Sendable {
    let title: String
    let count: Int
    let selectedProjectName: String?

    var id: String { selectedProjectName ?? "__all__" }
    var isAll: Bool { selectedProjectName == nil }
}

enum ImportSessionFilterSupport {
    static func projectFilters(from sessions: [ImportableSession]) -> [ImportSessionProjectFilter] {
        let projectCounts = Dictionary(grouping: sessions, by: \.projectName)
            .mapValues(\.count)

        let projectFilters = projectCounts.keys.sorted { lhs, rhs in
            lhs.localizedCaseInsensitiveCompare(rhs) == .orderedAscending
        }.map { projectName in
            ImportSessionProjectFilter(
                title: projectName,
                count: projectCounts[projectName] ?? 0,
                selectedProjectName: projectName
            )
        }

        return [
            ImportSessionProjectFilter(
                title: "All",
                count: sessions.count,
                selectedProjectName: nil
            )
        ] + projectFilters
    }

    static func filteredSessions(
        _ sessions: [ImportableSession],
        searchText: String,
        selectedProject: String?
    ) -> [ImportableSession] {
        let normalizedSearch = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        return sessions.filter { session in
            let matchesProject = selectedProject == nil || session.projectName == selectedProject
            guard matchesProject else { return false }

            guard !normalizedSearch.isEmpty else { return true }
            return session.projectName.lowercased().contains(normalizedSearch) ||
                session.firstMessage.lowercased().contains(normalizedSearch) ||
                (session.gitBranch?.lowercased().contains(normalizedSearch) ?? false)
        }
    }
}
