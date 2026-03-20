//
//  DataModels.swift
//  ClaudeIsland
//
//  SwiftData models for persistent storage of projects, threads, and messages.
//

import Foundation
import SwiftData

// MARK: - Project

/// A project represents a working directory (folder) that contains Claude sessions.
@Model
final class Project {
    @Attribute(.unique) var id: String
    var name: String
    var path: String

    @Relationship(deleteRule: .cascade, inverse: \Thread.project)
    var threads: [Thread] = []

    var createdAt: Date
    var updatedAt: Date

    init(
        id: String = UUID().uuidString,
        name: String,
        path: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.path = path
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// Extract project name from a file path (last path component)
    static func nameFromPath(_ path: String) -> String {
        URL(fileURLWithPath: path).lastPathComponent
    }
}

// MARK: - Thread

/// A conversation thread (session) within a project.
@Model
final class Thread {
    @Attribute(.unique) var id: String
    var project: Project?
    var title: String?

    /// How this thread was created
    var sourceRaw: String
    var source: ThreadSource {
        get { ThreadSource(rawValue: sourceRaw) ?? .app }
        set { sourceRaw = newValue.rawValue }
    }

    /// The Claude CLI session_id (used for --resume)
    var cliSessionId: String?

    /// Current git branch when the thread was created
    var gitBranch: String?

    /// Current thread status
    var statusRaw: String
    var status: ThreadStatus {
        get { ThreadStatus(rawValue: statusRaw) ?? .idle }
        set { statusRaw = newValue.rawValue }
    }

    @Relationship(deleteRule: .cascade, inverse: \Message.thread)
    var messages: [Message] = []

    var createdAt: Date
    var updatedAt: Date

    /// Total cost in USD for this thread
    var totalCostUsd: Double

    /// Total input tokens
    var totalTokensIn: Int

    /// Total output tokens
    var totalTokensOut: Int

    init(
        id: String = UUID().uuidString,
        project: Project? = nil,
        title: String? = nil,
        source: ThreadSource = .app,
        cliSessionId: String? = nil,
        gitBranch: String? = nil,
        status: ThreadStatus = .idle,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.project = project
        self.title = title
        self.sourceRaw = source.rawValue
        self.cliSessionId = cliSessionId
        self.gitBranch = gitBranch
        self.statusRaw = status.rawValue
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.totalCostUsd = 0
        self.totalTokensIn = 0
        self.totalTokensOut = 0
    }
}

enum ThreadSource: String, Codable, CaseIterable {
    case app        // Created in the app
    case imported   // Imported from Claude CLI
    case takeover   // Taken over from global monitor
}

enum ThreadStatus: String, Codable, CaseIterable {
    case idle       // No active CLI process
    case active     // CLI process running
    case ended      // Session ended / archived
}

// MARK: - Message

/// A single message in a conversation thread.
@Model
final class Message {
    @Attribute(.unique) var id: String
    var thread: Thread?

    /// Message role
    var roleRaw: String
    var role: MessageRole {
        get { MessageRole(rawValue: roleRaw) ?? .assistant }
        set { roleRaw = newValue.rawValue }
    }

    /// Main text content
    var content: String

    /// Thinking/reasoning content (assistant only)
    var thinking: String?

    /// Tool name if this is a tool use/result message
    var toolName: String?

    /// Tool input as JSON string
    var toolInput: String?

    /// Tool result as JSON string
    var toolResult: String?

    /// Cost in USD for this message
    var costUsd: Double?

    /// Input tokens
    var tokensIn: Int?

    /// Output tokens
    var tokensOut: Int?

    var createdAt: Date

    init(
        id: String = UUID().uuidString,
        thread: Thread? = nil,
        role: MessageRole = .user,
        content: String,
        thinking: String? = nil,
        toolName: String? = nil,
        toolInput: String? = nil,
        toolResult: String? = nil,
        costUsd: Double? = nil,
        tokensIn: Int? = nil,
        tokensOut: Int? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.thread = thread
        self.roleRaw = role.rawValue
        self.content = content
        self.thinking = thinking
        self.toolName = toolName
        self.toolInput = toolInput
        self.toolResult = toolResult
        self.costUsd = costUsd
        self.tokensIn = tokensIn
        self.tokensOut = tokensOut
        self.createdAt = createdAt
    }
}

enum MessageRole: String, Codable, CaseIterable {
    case user
    case assistant
    case system
}

// MARK: - ImportRecord

/// Tracks which CLI sessions have been imported to prevent duplicates.
@Model
final class ImportRecord {
    /// The original Claude CLI session_id
    @Attribute(.unique) var cliSessionId: String

    /// When the import occurred
    var importedAt: Date

    /// Reference to the imported thread's id
    var threadId: String?

    init(
        cliSessionId: String,
        importedAt: Date = Date(),
        threadId: String? = nil
    ) {
        self.cliSessionId = cliSessionId
        self.importedAt = importedAt
        self.threadId = threadId
    }
}
