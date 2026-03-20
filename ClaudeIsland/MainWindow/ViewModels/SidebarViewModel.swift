//
//  SidebarViewModel.swift
//  ClaudeIsland
//
//  ViewModel for the main window sidebar.
//  Handles dual mode (My Sessions / Global Monitor), search, and project grouping.
//

import Foundation
import SwiftData
import os.log

private let logger = Logger(subsystem: "com.claudeisland", category: "Sidebar")

// MARK: - Sidebar Mode

enum SidebarMode: String, CaseIterable {
    case mySessions = "My Sessions"
    case globalMonitor = "Global Monitor"

    var icon: String {
        switch self {
        case .mySessions: return "bubble.left.and.text.bubble.right"
        case .globalMonitor: return "globe"
        }
    }
}

// MARK: - ProjectGroup (UI grouping)

struct ProjectGroup: Identifiable {
    let id: String
    let name: String
    let path: String
    var threads: [ThreadDTO]
}

// MARK: - SidebarViewModel

@Observable
@MainActor
final class SidebarViewModel {

    // MARK: - State

    var mode: SidebarMode = .mySessions
    var searchText: String = ""
    var selectedThreadId: String?
    var projects: [ProjectGroup] = []
    var isLoading = false
    var showImportSheet = false

    // Global monitor sessions (from Hook events)
    var globalSessions: [HookSessionInfo] = []

    // MARK: - Dependencies

    private var dataActor: BackgroundDataActor?

    // MARK: - Init

    func configure(with container: ModelContainer) {
        self.dataActor = BackgroundDataActor(modelContainer: container)
    }

    // MARK: - Data Loading

    func loadData() async {
        isLoading = true
        defer { isLoading = false }

        guard let actor = dataActor else { return }

        do {
            let allProjects = try await actor.fetchAllProjects()
            var groups: [ProjectGroup] = []

            for project in allProjects {
                let threads = try await actor.fetchThreads(projectId: project.id)
                let filtered = filterThreads(threads)
                if !filtered.isEmpty {
                    groups.append(ProjectGroup(
                        id: project.id,
                        name: project.name,
                        path: project.path,
                        threads: filtered
                    ))
                }
            }

            self.projects = groups
        } catch {
            logger.error("Failed to load data: \(error)")
        }
    }

    // MARK: - Thread Actions

    func createNewThread(projectPath: String) async -> String? {
        guard let actor = dataActor else { return nil }

        do {
            let projectId = try await actor.findOrCreateProject(path: projectPath)

            // Detect git branch
            let gitBranch = detectGitBranch(at: projectPath)

            let threadId = try await actor.createThread(
                projectId: projectId,
                source: .app,
                gitBranch: gitBranch
            )

            await loadData()
            selectedThreadId = threadId
            return threadId
        } catch {
            logger.error("Failed to create thread: \(error)")
            return nil
        }
    }

    func deleteThread(id: String) async {
        guard let actor = dataActor else { return }

        do {
            try await actor.deleteThread(threadId: id)
            if selectedThreadId == id {
                selectedThreadId = nil
            }
            await loadData()
        } catch {
            logger.error("Failed to delete thread: \(error)")
        }
    }

    // MARK: - Takeover (Global → My Sessions)

    func takeoverSession(_ session: HookSessionInfo) async -> String? {
        guard let actor = dataActor else { return nil }

        do {
            let projectId = try await actor.findOrCreateProject(path: session.projectPath)
            let threadId = try await actor.createThread(
                projectId: projectId,
                title: session.title,
                source: .takeover,
                cliSessionId: session.sessionId,
                gitBranch: session.gitBranch
            )

            // Switch to My Sessions mode
            mode = .mySessions
            selectedThreadId = threadId
            await loadData()
            return threadId
        } catch {
            logger.error("Failed to takeover session: \(error)")
            return nil
        }
    }

    // MARK: - Private

    private func filterThreads(_ threads: [ThreadDTO]) -> [ThreadDTO] {
        guard !searchText.isEmpty else { return threads }
        let query = searchText.lowercased()
        return threads.filter { thread in
            (thread.title?.lowercased().contains(query) ?? false) ||
            (thread.gitBranch?.lowercased().contains(query) ?? false)
        }
    }

    private func detectGitBranch(at path: String) -> String? {
        let headPath = URL(fileURLWithPath: path)
            .appendingPathComponent(".git/HEAD")
        guard let content = try? String(contentsOf: headPath, encoding: .utf8) else {
            return nil
        }
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("ref: refs/heads/") {
            return String(trimmed.dropFirst("ref: refs/heads/".count))
        }
        return String(trimmed.prefix(8)) // Short SHA
    }
}

// MARK: - HookSessionInfo

/// Represents a session detected by the Hook Monitor (global mode)
struct HookSessionInfo: Identifiable, Sendable {
    let id: String  // session_id
    let sessionId: String
    let projectPath: String
    let projectName: String
    let title: String?
    let gitBranch: String?
    let status: String  // "processing", "waitingForInput", "waitingForApproval", "ended"
    let startedAt: Date
    var lastEventAt: Date
    var messageCount: Int
}
