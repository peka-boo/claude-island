//
//  DataStore.swift
//  ClaudeIsland
//
//  Central data store providing SwiftData ModelContainer and convenience methods.
//  Uses ModelActor for thread-safe background operations.
//

import Foundation
import SwiftData

// MARK: - DataStore

/// Provides the shared SwiftData ModelContainer for the app.
enum DataStore {
    /// The shared model container, configured with WAL journal mode.
    static let shared: ModelContainer = {
        let schema = Schema([
            Project.self,
            Thread.self,
            Message.self,
            ImportRecord.self,
        ])

        // Store in ~/.claude-island/ directory
        let appDataDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude-island")

        // Ensure directory exists
        try? FileManager.default.createDirectory(
            at: appDataDir,
            withIntermediateDirectories: true
        )

        let dbURL = appDataDir.appendingPathComponent("data.store")

        let config = ModelConfiguration(
            "ClaudeIslandStore",
            schema: schema,
            url: dbURL,
            allowsSave: true
        )

        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }()
}

// MARK: - BackgroundDataActor

/// A ModelActor for performing database operations off the main thread.
@ModelActor
actor BackgroundDataActor {

    // MARK: - Project Operations

    /// Find or create a project for the given path
    func findOrCreateProject(path: String) throws -> String {
        let descriptor = FetchDescriptor<Project>(
            predicate: #Predicate { $0.path == path }
        )

        if let existing = try modelContext.fetch(descriptor).first {
            return existing.id
        }

        let name = Project.nameFromPath(path)
        let project = Project(name: name, path: path)
        modelContext.insert(project)
        try modelContext.save()
        return project.id
    }

    /// Fetch all projects sorted by updated date
    func fetchAllProjects() throws -> [ProjectDTO] {
        let descriptor = FetchDescriptor<Project>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        return try modelContext.fetch(descriptor).map { ProjectDTO(from: $0) }
    }

    /// Fetch a single project
    func fetchProject(projectId: String) throws -> ProjectDTO? {
        let descriptor = FetchDescriptor<Project>(
            predicate: #Predicate { $0.id == projectId }
        )
        return try modelContext.fetch(descriptor).first.map(ProjectDTO.init(from:))
    }

    // MARK: - Thread Operations

    /// Create a new thread
    func createThread(
        projectId: String,
        title: String? = nil,
        source: ThreadSource = .app,
        cliSessionId: String? = nil,
        gitBranch: String? = nil,
        createdAt: Date? = nil,
        updatedAt: Date? = nil
    ) throws -> String {
        let projectDescriptor = FetchDescriptor<Project>(
            predicate: #Predicate { $0.id == projectId }
        )
        guard let project = try modelContext.fetch(projectDescriptor).first else {
            throw DataStoreError.projectNotFound(projectId)
        }

        let thread = Thread(
            project: project,
            title: title,
            source: source,
            cliSessionId: normalizeCLISessionId(cliSessionId),
            gitBranch: gitBranch,
            createdAt: createdAt ?? Date(),
            updatedAt: updatedAt ?? createdAt ?? Date()
        )
        modelContext.insert(thread)

        project.updatedAt = max(project.updatedAt, thread.updatedAt)
        try modelContext.save()
        return thread.id
    }

    /// Fetch threads for a project
    func fetchThreads(projectId: String) throws -> [ThreadDTO] {
        let descriptor = FetchDescriptor<Thread>(
            predicate: #Predicate { $0.project?.id == projectId },
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        return try modelContext.fetch(descriptor).map { ThreadDTO(from: $0) }
    }

    /// Fetch all threads sorted by updated date
    func fetchAllThreads() throws -> [ThreadDTO] {
        let descriptor = FetchDescriptor<Thread>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        return try modelContext.fetch(descriptor).map { ThreadDTO(from: $0) }
    }

    /// Fetch a single thread
    func fetchThread(threadId: String) throws -> ThreadDTO? {
        let descriptor = FetchDescriptor<Thread>(
            predicate: #Predicate { $0.id == threadId }
        )
        return try modelContext.fetch(descriptor).first.map(ThreadDTO.init(from:))
    }

    /// Find the latest thread that already owns a Claude CLI session id.
    func fetchThreadId(cliSessionId: String) throws -> String? {
        guard let normalizedId = normalizeCLISessionId(cliSessionId) else {
            return nil
        }

        let legacyId = normalizedId + ".jsonl"
        let descriptor = FetchDescriptor<Thread>(
            predicate: #Predicate { $0.cliSessionId == normalizedId || $0.cliSessionId == legacyId },
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )

        return try modelContext.fetch(descriptor).first?.id
    }

    /// Update thread status
    func updateThreadStatus(threadId: String, status: ThreadStatus) throws {
        let descriptor = FetchDescriptor<Thread>(
            predicate: #Predicate { $0.id == threadId }
        )
        guard let thread = try modelContext.fetch(descriptor).first else { return }
        thread.status = status
        thread.updatedAt = Date()
        try modelContext.save()
    }

    /// Update thread runtime metadata without forcing callers to fetch and re-save models.
    func updateThreadRuntime(
        threadId: String,
        status: ThreadStatus? = nil,
        cliSessionId: String? = nil
    ) throws {
        let descriptor = FetchDescriptor<Thread>(
            predicate: #Predicate { $0.id == threadId }
        )
        guard let thread = try modelContext.fetch(descriptor).first else { return }

        if let status {
            thread.status = status
        }
        if let cliSessionId = normalizeCLISessionId(cliSessionId) {
            thread.cliSessionId = cliSessionId
        }

        thread.updatedAt = Date()
        try modelContext.save()
    }

    /// Update thread title
    func updateThreadTitle(threadId: String, title: String) throws {
        let descriptor = FetchDescriptor<Thread>(
            predicate: #Predicate { $0.id == threadId }
        )
        guard let thread = try modelContext.fetch(descriptor).first else { return }
        thread.title = title
        thread.updatedAt = Date()
        try modelContext.save()
    }

    // MARK: - Message Operations

    /// Append a message to a thread
    func appendMessage(
        threadId: String,
        role: MessageRole,
        content: String,
        thinking: String? = nil,
        toolName: String? = nil,
        toolInput: String? = nil,
        toolResult: String? = nil,
        costUsd: Double? = nil,
        tokensIn: Int? = nil,
        tokensOut: Int? = nil,
        createdAt: Date? = nil
    ) throws -> String {
        let threadDescriptor = FetchDescriptor<Thread>(
            predicate: #Predicate { $0.id == threadId }
        )
        guard let thread = try modelContext.fetch(threadDescriptor).first else {
            throw DataStoreError.threadNotFound(threadId)
        }

        let message = Message(
            thread: thread,
            role: role,
            content: content,
            thinking: thinking,
            toolName: toolName,
            toolInput: toolInput,
            toolResult: toolResult,
            costUsd: costUsd,
            tokensIn: tokensIn,
            tokensOut: tokensOut,
            createdAt: createdAt ?? Date()
        )
        modelContext.insert(message)

        // Update thread stats
        if let cost = costUsd { thread.totalCostUsd += cost }
        if let tin = tokensIn { thread.totalTokensIn += tin }
        if let tout = tokensOut { thread.totalTokensOut += tout }
        thread.updatedAt = max(thread.updatedAt, message.createdAt)
        if let project = thread.project {
            project.updatedAt = max(project.updatedAt, message.createdAt)
        }

        // Auto-set title from first user message
        if thread.title == nil, role == .user {
            let maxLen = 60
            thread.title = content.count > maxLen
                ? String(content.prefix(maxLen)) + "..."
                : content
        }

        try modelContext.save()
        return message.id
    }

    /// Fetch all messages for a thread
    func fetchMessages(threadId: String) throws -> [MessageDTO] {
        let descriptor = FetchDescriptor<Message>(
            predicate: #Predicate { $0.thread?.id == threadId },
            sortBy: [SortDescriptor(\.createdAt, order: .forward)]
        )
        return try modelContext.fetch(descriptor).map { MessageDTO(from: $0) }
    }

    /// Fetch the latest messages for a thread in ascending display order.
    func fetchRecentMessages(threadId: String, limit: Int) throws -> [MessageDTO] {
        try fetchMessagePage(threadId: threadId, limit: limit)
    }

    /// Fetch messages older than the provided message, keeping ascending display order.
    func fetchMessagesBefore(
        threadId: String,
        beforeMessageId: String,
        beforeCreatedAt: Date,
        limit: Int
    ) throws -> [MessageDTO] {
        try fetchMessagePage(
            threadId: threadId,
            limit: limit,
            beforeMessageId: beforeMessageId,
            beforeCreatedAt: beforeCreatedAt
        )
    }

    private func fetchMessagePage(
        threadId: String,
        limit: Int,
        beforeMessageId: String? = nil,
        beforeCreatedAt: Date? = nil
    ) throws -> [MessageDTO] {
        guard limit > 0 else { return [] }

        let descriptor: FetchDescriptor<Message>
        if let beforeMessageId, let beforeCreatedAt {
            descriptor = FetchDescriptor<Message>(
                predicate: #Predicate {
                    $0.thread?.id == threadId &&
                    (
                        $0.createdAt < beforeCreatedAt ||
                        ($0.createdAt == beforeCreatedAt && $0.id < beforeMessageId)
                    )
                },
                sortBy: [
                    SortDescriptor(\.createdAt, order: .reverse),
                    SortDescriptor(\.id, order: .reverse)
                ]
            )
        } else {
            descriptor = FetchDescriptor<Message>(
                predicate: #Predicate { $0.thread?.id == threadId },
                sortBy: [
                    SortDescriptor(\.createdAt, order: .reverse),
                    SortDescriptor(\.id, order: .reverse)
                ]
            )
        }

        var limitedDescriptor = descriptor
        limitedDescriptor.fetchLimit = limit

        let page = try modelContext.fetch(limitedDescriptor).map(MessageDTO.init(from:))
        return Array(page.reversed())
    }

    /// Clear a thread's stored conversation while preserving the thread itself.
    func clearThreadConversation(threadId: String) throws {
        let threadDescriptor = FetchDescriptor<Thread>(
            predicate: #Predicate { $0.id == threadId }
        )

        guard let thread = try modelContext.fetch(threadDescriptor).first else {
            throw DataStoreError.threadNotFound(threadId)
        }

        let messageDescriptor = FetchDescriptor<Message>(
            predicate: #Predicate { $0.thread?.id == threadId }
        )

        let messages = try modelContext.fetch(messageDescriptor)
        for message in messages {
            modelContext.delete(message)
        }

        thread.cliSessionId = nil
        thread.status = .idle
        thread.totalCostUsd = 0
        thread.totalTokensIn = 0
        thread.totalTokensOut = 0
        thread.updatedAt = Date()
        if let project = thread.project {
            project.updatedAt = Date()
        }

        try modelContext.save()
    }

    // MARK: - Import Tracking

    /// Check if a CLI session has already been imported
    func isImported(cliSessionId: String) throws -> Bool {
        guard let normalizedId = normalizeCLISessionId(cliSessionId) else {
            return false
        }
        let matchingRecords = try fetchImportRecords(for: normalizedId)
        guard !matchingRecords.isEmpty else { return false }

        if let thread = try fetchImportedThread(forNormalizedSessionId: normalizedId) {
            let threadId = thread.id
            var needsSave = false

            for record in matchingRecords {
                if record.cliSessionId != normalizedId {
                    record.cliSessionId = normalizedId
                    needsSave = true
                }

                if record.threadId != threadId {
                    record.threadId = threadId
                    needsSave = true
                }
            }

            if needsSave {
                try modelContext.save()
            }

            return true
        }

        for record in matchingRecords {
            modelContext.delete(record)
        }
        try modelContext.save()
        return false
    }

    /// Record that a CLI session was imported
    func recordImport(cliSessionId: String, threadId: String) throws {
        guard let normalizedId = normalizeCLISessionId(cliSessionId) else { return }
        let matchingRecords = try fetchImportRecords(for: normalizedId)

        if let primaryRecord = matchingRecords.first {
            primaryRecord.cliSessionId = normalizedId
            primaryRecord.threadId = threadId
            primaryRecord.importedAt = Date()

            for duplicate in matchingRecords.dropFirst() {
                modelContext.delete(duplicate)
            }
        } else {
            let record = ImportRecord(
                cliSessionId: normalizedId,
                threadId: threadId
            )
            modelContext.insert(record)
        }

        try modelContext.save()
    }

    // MARK: - Delete

    /// Delete a thread and all its messages
    func deleteThread(threadId: String) throws {
        try deleteImportRecords(linkedToThreadId: threadId)

        let descriptor = FetchDescriptor<Thread>(
            predicate: #Predicate { $0.id == threadId }
        )
        guard let thread = try modelContext.fetch(descriptor).first else { return }
        modelContext.delete(thread) // Cascade deletes messages
        try modelContext.save()
    }

    /// Delete a project and all its threads/messages
    func deleteProject(projectId: String) throws {
        let descriptor = FetchDescriptor<Project>(
            predicate: #Predicate { $0.id == projectId }
        )
        guard let project = try modelContext.fetch(descriptor).first else { return }

        let threadIds = project.threads.map(\.id)
        for threadId in threadIds {
            try deleteImportRecords(linkedToThreadId: threadId)
        }

        modelContext.delete(project) // Cascade deletes threads → messages
        try modelContext.save()
    }

    private func fetchImportRecords(for normalizedSessionId: String) throws -> [ImportRecord] {
        let legacyId = normalizedSessionId + ".jsonl"
        let descriptor = FetchDescriptor<ImportRecord>(
            predicate: #Predicate { $0.cliSessionId == normalizedSessionId || $0.cliSessionId == legacyId }
        )
        return try modelContext.fetch(descriptor)
    }

    private func fetchImportedThread(forNormalizedSessionId normalizedSessionId: String) throws -> Thread? {
        let legacyId = normalizedSessionId + ".jsonl"
        let descriptor = FetchDescriptor<Thread>(
            predicate: #Predicate { $0.cliSessionId == normalizedSessionId || $0.cliSessionId == legacyId }
        )
        return try modelContext.fetch(descriptor).first
    }

    private func deleteImportRecords(linkedToThreadId threadId: String) throws {
        let descriptor = FetchDescriptor<ImportRecord>(
            predicate: #Predicate { $0.threadId == threadId }
        )

        for record in try modelContext.fetch(descriptor) {
            modelContext.delete(record)
        }
    }
}

// MARK: - DTOs (Data Transfer Objects)

/// Lightweight value types for passing data across actor boundaries.
/// SwiftData @Model objects cannot cross actor boundaries directly.

struct ProjectDTO: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let path: String
    let threadCount: Int
    let createdAt: Date
    let updatedAt: Date

    init(from project: Project) {
        self.id = project.id
        self.name = project.name
        self.path = project.path
        self.threadCount = project.threads.count
        self.createdAt = project.createdAt
        self.updatedAt = project.updatedAt
    }
}

struct ThreadDTO: Identifiable, Equatable, Sendable {
    let id: String
    let projectId: String?
    let projectName: String?
    let title: String?
    let source: ThreadSource
    let cliSessionId: String?
    let gitBranch: String?
    let status: ThreadStatus
    let totalCostUsd: Double
    let totalTokensIn: Int
    let totalTokensOut: Int
    let messageCount: Int
    let createdAt: Date
    let updatedAt: Date

    init(from thread: Thread) {
        self.id = thread.id
        self.projectId = thread.project?.id
        self.projectName = thread.project?.name
        self.title = thread.title
        self.source = thread.source
        self.cliSessionId = thread.cliSessionId
        self.gitBranch = thread.gitBranch
        self.status = thread.status
        self.totalCostUsd = thread.totalCostUsd
        self.totalTokensIn = thread.totalTokensIn
        self.totalTokensOut = thread.totalTokensOut
        self.messageCount = thread.messages.count
        self.createdAt = thread.createdAt
        self.updatedAt = thread.updatedAt
    }
}

struct MessageDTO: Identifiable, Equatable, Sendable {
    let id: String
    let threadId: String?
    let role: MessageRole
    let content: String
    let thinking: String?
    let toolName: String?
    let toolInput: String?
    let toolResult: String?
    let costUsd: Double?
    let tokensIn: Int?
    let tokensOut: Int?
    let createdAt: Date

    init(from message: Message) {
        self.id = message.id
        self.threadId = message.thread?.id
        self.role = message.role
        self.content = message.content
        self.thinking = message.thinking
        self.toolName = message.toolName
        self.toolInput = message.toolInput
        self.toolResult = message.toolResult
        self.costUsd = message.costUsd
        self.tokensIn = message.tokensIn
        self.tokensOut = message.tokensOut
        self.createdAt = message.createdAt
    }
}

// MARK: - Errors

enum DataStoreError: LocalizedError {
    case projectNotFound(String)
    case threadNotFound(String)

    var errorDescription: String? {
        switch self {
        case .projectNotFound(let id): return "Project not found: \(id)"
        case .threadNotFound(let id): return "Thread not found: \(id)"
        }
    }
}
