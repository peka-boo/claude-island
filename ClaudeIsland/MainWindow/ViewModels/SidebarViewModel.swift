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

typealias ProjectGroup = SidebarProjectGroup<ThreadDTO>

extension ThreadDTO: SidebarProjectGroupItem {
    var sidebarProjectId: String? { projectId }
    var sidebarUpdatedAt: Date { updatedAt }
}

extension ProjectGroup {
    init(id: String, name: String, path: String, updatedAt: Date, threads: [ThreadDTO]) {
        self.init(
            id: id,
            name: name,
            path: path,
            updatedAt: updatedAt,
            items: threads
        )
    }

    var threads: [ThreadDTO] {
        get { items }
        set { items = newValue }
    }
}

// MARK: - SidebarViewModel

@Observable
@MainActor
final class SidebarViewModel {

    private static let collapsedProjectsDefaultsKey = "mainWindow.collapsedProjectIDs"

    // MARK: - State

    var mode: SidebarMode = .mySessions
    var searchText: String = "" {
        didSet {
            searchDebounceTask?.cancel()
            searchDebounceTask = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 300_000_000) // 300ms debounce
                guard !Task.isCancelled else { return }
                self?.applySearch()
            }
        }
    }
    var showAllSessions: Bool = false
    var selectedSessionIdentity: SidebarSessionIdentity?
    var selectedThreadId: String?
    var projects: [ProjectGroup] = []
    var globalSessionGroups: [GlobalSessionGroup] = []
    var isLoading = false
    var showImportSheet = false
    var collapsedProjectIDs: Set<String> = Set(
        UserDefaults.standard.stringArray(forKey: SidebarViewModel.collapsedProjectsDefaultsKey) ?? []
    )

    // Global monitor sessions (live + scanned CLI history)
    var globalSessions: [HookSessionInfo] = []

    // MARK: - Dependencies

    private var dataActor: BackgroundDataActor?
    private var allProjects: [ProjectGroup] = []
    private var scannedGlobalSessions: [ImportableSession] = []
    private var liveGlobalSessions: [HookSessionInfo] = []
    private var threadsById: [String: ThreadDTO] = [:]
    private var globalSessionsByNormalizedId: [String: HookSessionInfo] = [:]
    private var searchDebounceTask: Task<Void, Never>?

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
            async let scannedSessionsTask = CLISessionScanner.scan()
            let allProjects = try await actor.fetchAllProjects()
            let allThreads = try await actor.fetchAllThreads()
            let groups = SidebarProjectGroupingSupport.groups(
                projects: allProjects.map {
                    SidebarProjectRecord(
                        id: $0.id,
                        name: $0.name,
                        path: $0.path,
                        updatedAt: $0.updatedAt
                    )
                },
                items: allThreads
            )

            self.allProjects = groups
            rebuildThreadIndex(from: groups)
            scannedGlobalSessions = await scannedSessionsTask
            updateLiveMonitorSessions(ClaudeSessionMonitor.shared.instances)
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
            selectThread(threadId: threadId, cliSessionId: nil)
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
                clearSelection()
            }
            await loadData()
        } catch {
            logger.error("Failed to delete thread: \(error)")
        }
    }

    func isProjectCollapsed(_ projectId: String) -> Bool {
        collapsedProjectIDs.contains(projectId)
    }

    func toggleProjectCollapse(_ projectId: String) {
        if collapsedProjectIDs.contains(projectId) {
            collapsedProjectIDs.remove(projectId)
        } else {
            collapsedProjectIDs.insert(projectId)
        }

        UserDefaults.standard.set(
            Array(collapsedProjectIDs).sorted(),
            forKey: SidebarViewModel.collapsedProjectsDefaultsKey
        )
    }

    func updateLiveMonitorSessions(_ sessions: [SessionState]) {
        liveGlobalSessions = sessions.map { session in
            HookSessionInfo(
                id: session.sessionId,
                sessionId: session.sessionId,
                projectPath: session.cwd,
                projectName: session.projectName,
                title: session.displayTitle,
                gitBranch: nil,
                status: phaseStatus(for: session.phase),
                startedAt: session.createdAt,
                lastEventAt: session.lastActivity,
                messageCount: session.chatItems.count,
                source: .live
            )
        }

        applySearch()
    }

    func refreshGlobalSessions() async {
        scannedGlobalSessions = await CLISessionScanner.scan()
        updateLiveMonitorSessions(ClaudeSessionMonitor.shared.instances)
    }

    func refreshThreadSnapshot(_ thread: ThreadDTO?) {
        guard let thread, threadsById[thread.id] != nil else { return }

        threadsById[thread.id] = thread
        allProjects = SidebarProjectGroupingSupport.replacingItem(thread, in: allProjects)
        applySearch()
    }

    func selectThread(_ thread: ThreadDTO) {
        selectThread(threadId: thread.id, cliSessionId: thread.cliSessionId)
    }

    func isSelected(_ thread: ThreadDTO) -> Bool {
        selectedSessionIdentity == GlobalSessionSupport.selectionIdentity(
            threadId: thread.id,
            cliSessionId: thread.cliSessionId
        )
    }

    func isSelected(_ session: HookSessionInfo) -> Bool {
        selectedSessionIdentity == GlobalSessionSupport.selectionIdentity(sessionId: session.sessionId)
    }

    func displayStatus(for thread: ThreadDTO) -> SidebarSessionStatus {
        let linkedSession = linkedGlobalSession(for: thread)
        return GlobalSessionSupport.resolvedStatus(
            threadStatus: thread.status.rawValue,
            sessionStatus: linkedSession?.status
        )
    }

    func displayStatus(for session: HookSessionInfo) -> SidebarSessionStatus {
        GlobalSessionSupport.resolvedStatus(
            threadStatus: "idle",
            sessionStatus: session.status
        )
    }

    func displayLastEventAt(for thread: ThreadDTO) -> Date {
        GlobalSessionSupport.resolvedLastEventAt(
            threadUpdatedAt: thread.updatedAt,
            sessionLastEventAt: linkedGlobalSession(for: thread)?.lastEventAt
        )
    }

    func displayTitle(for thread: ThreadDTO) -> String {
        thread.title ?? linkedGlobalSession(for: thread)?.title ?? "New Chat"
    }

    func displayGitBranch(for thread: ThreadDTO) -> String? {
        thread.gitBranch ?? linkedGlobalSession(for: thread)?.gitBranch
    }

    private func selectThread(threadId: String, cliSessionId: String?) {
        selectedThreadId = threadId
        selectedSessionIdentity = GlobalSessionSupport.selectionIdentity(
            threadId: threadId,
            cliSessionId: cliSessionId
        )
    }

    // MARK: - Takeover (Global → My Sessions)

    func openGlobalSession(_ session: HookSessionInfo, switchModeToMySessions: Bool = false) async -> String? {
        guard let actor = dataActor else { return nil }
        let normalizedSessionId = normalizeCLISessionId(session.sessionId) ?? session.sessionId

        do {
            let existingThreadId = try await actor.fetchThreadId(cliSessionId: normalizedSessionId)

            let threadId: String
            switch GlobalSessionSupport.openAction(existingThreadId: existingThreadId) {
            case .openExistingThread(let existingThreadId):
                threadId = existingThreadId
            case .createTakeoverThread:
                let projectId = try await actor.findOrCreateProject(path: session.projectPath)
                threadId = try await actor.createThread(
                    projectId: projectId,
                    title: session.title,
                    source: .takeover,
                    cliSessionId: normalizedSessionId,
                    gitBranch: session.gitBranch
                )
                try await actor.recordImport(cliSessionId: normalizedSessionId, threadId: threadId)
            }

            if switchModeToMySessions {
                mode = .mySessions
            }
            selectedThreadId = threadId
            selectedSessionIdentity = GlobalSessionSupport.selectionIdentity(sessionId: normalizedSessionId)
            await loadData()
            return threadId
        } catch {
            logger.error("Failed to open global session: \(error)")
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

    func applySearch() {
        if searchText.isEmpty {
            projects = allProjects
        } else {
            projects = allProjects.compactMap { group in
                let filteredThreads = filterThreads(group.threads)
                guard !filteredThreads.isEmpty else { return nil }

                return ProjectGroup(
                    id: group.id,
                    name: group.name,
                    path: group.path,
                    updatedAt: group.updatedAt,
                    threads: filteredThreads
                )
            }
        }

        let mergedGlobalSessions = GlobalSessionSupport.mergedSessions(
            live: liveGlobalSessions,
            scanned: scannedGlobalSessions,
            searchText: ""
        ).filter { session in
            // Apply same filtering as globalSessions
            showAllSessions || session.source == .live
        }
        globalSessionsByNormalizedId = Dictionary(
            uniqueKeysWithValues: mergedGlobalSessions.map { session in
                let normalizedSessionId = normalizeCLISessionId(session.sessionId) ?? session.sessionId
                return (normalizedSessionId, session)
            }
        )
        let allMergedSessions = GlobalSessionSupport.mergedSessions(
            live: liveGlobalSessions,
            scanned: scannedGlobalSessions,
            searchText: searchText
        )
        
        // Filter to show only active sessions (live) unless showAllSessions is true
        if showAllSessions {
            globalSessions = allMergedSessions
        } else {
            globalSessions = allMergedSessions.filter { $0.source == .live }
        }
        globalSessionGroups = GlobalSessionSupport.groupedSessions(globalSessions)
        reconcileSelectionState()
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

    private func phaseStatus(for phase: SessionPhase) -> String {
        switch phase {
        case .idle:
            return "idle"
        case .processing:
            return "processing"
        case .waitingForInput:
            return "waitingForInput"
        case .waitingForApproval:
            return "waitingForApproval"
        case .compacting:
            return "compacting"
        case .ended:
            return "ended"
        }
    }

    private func clearSelection() {
        selectedThreadId = nil
        selectedSessionIdentity = nil
    }

    private func rebuildThreadIndex(from groups: [ProjectGroup]) {
        threadsById = Dictionary(
            uniqueKeysWithValues: groups
                .flatMap(\.threads)
                .map { ($0.id, $0) }
        )
    }

    private func reconcileSelectionState() {
        guard let selectedThreadId else { return }
        guard let selectedThread = threadsById[selectedThreadId] else {
            clearSelection()
            return
        }

        selectedSessionIdentity = GlobalSessionSupport.selectionIdentity(
            threadId: selectedThread.id,
            cliSessionId: selectedThread.cliSessionId
        )
    }

    private func linkedGlobalSession(for thread: ThreadDTO) -> HookSessionInfo? {
        guard let normalizedSessionId = normalizeCLISessionId(thread.cliSessionId) else {
            return nil
        }

        return globalSessionsByNormalizedId[normalizedSessionId]
    }
}
