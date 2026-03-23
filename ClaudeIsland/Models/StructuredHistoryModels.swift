//
//  StructuredHistoryModels.swift
//  ClaudeIsland
//
//  Shared structured chat history models used by both notch and main window surfaces.
//

import Foundation

struct ChatHistoryItem: Identifiable, Equatable, Sendable {
    let id: String
    let type: ChatHistoryItemType
    let timestamp: Date

    static func == (lhs: ChatHistoryItem, rhs: ChatHistoryItem) -> Bool {
        lhs.id == rhs.id && lhs.type == rhs.type
    }
}

enum ChatHistoryItemType: Equatable, Sendable {
    case user(String)
    case assistant(String)
    case toolCall(ToolCallItem)
    case thinking(String)
    case interrupted
}

struct ToolCallItem: Equatable, Sendable {
    let name: String
    let input: [String: String]
    var status: ToolStatus
    var result: String?
    var structuredResult: ToolResultData?
    var subagentTools: [SubagentToolCall]

    var inputPreview: String {
        if let filePath = input["file_path"] ?? input["path"] {
            return URL(fileURLWithPath: filePath).lastPathComponent
        }
        if let command = input["command"] {
            let firstLine = command.components(separatedBy: "\n").first ?? command
            return String(firstLine.prefix(60))
        }
        if let pattern = input["pattern"] {
            return pattern
        }
        if let query = input["query"] {
            return query
        }
        if let url = input["url"] {
            return url
        }
        if let agentId = input["agentId"] {
            let blocking = input["block"] == "true"
            return blocking ? "Waiting..." : "Checking \(agentId.prefix(8))..."
        }
        return input.values.first.map { String($0.prefix(60)) } ?? ""
    }

    var statusDisplay: ToolStatusDisplay {
        if status == .running {
            return ToolStatusDisplay.running(for: name, input: input)
        }
        if status == .waitingForApproval {
            return ToolStatusDisplay(text: "Waiting for approval...", isRunning: true)
        }
        if status == .interrupted {
            return ToolStatusDisplay(text: "Interrupted", isRunning: false)
        }
        return ToolStatusDisplay.completed(for: name, result: structuredResult)
    }

    static func == (lhs: ToolCallItem, rhs: ToolCallItem) -> Bool {
        lhs.name == rhs.name &&
        lhs.input == rhs.input &&
        lhs.status == rhs.status &&
        lhs.result == rhs.result &&
        lhs.structuredResult == rhs.structuredResult &&
        lhs.subagentTools == rhs.subagentTools
    }
}

enum ToolStatus: Sendable, CustomStringConvertible {
    case running
    case waitingForApproval
    case success
    case error
    case interrupted

    nonisolated var description: String {
        switch self {
        case .running: return "running"
        case .waitingForApproval: return "waitingForApproval"
        case .success: return "success"
        case .error: return "error"
        case .interrupted: return "interrupted"
        }
    }
}

extension ToolStatus: Equatable {
    nonisolated static func == (lhs: ToolStatus, rhs: ToolStatus) -> Bool {
        switch (lhs, rhs) {
        case (.running, .running): return true
        case (.waitingForApproval, .waitingForApproval): return true
        case (.success, .success): return true
        case (.error, .error): return true
        case (.interrupted, .interrupted): return true
        default: return false
        }
    }
}

struct SubagentToolCall: Equatable, Identifiable, Sendable {
    let id: String
    let name: String
    let input: [String: String]
    var status: ToolStatus
    let timestamp: Date

    var displayText: String {
        switch name {
        case "Read":
            if let path = input["file_path"] {
                return URL(fileURLWithPath: path).lastPathComponent
            }
            return "Reading..."
        case "Grep":
            if let pattern = input["pattern"] {
                return "grep: \(pattern)"
            }
            return "Searching..."
        case "Glob":
            if let pattern = input["pattern"] {
                return "glob: \(pattern)"
            }
            return "Finding files..."
        case "Bash":
            if let desc = input["description"] {
                return desc
            }
            if let cmd = input["command"] {
                let firstLine = cmd.components(separatedBy: "\n").first ?? cmd
                return String(firstLine.prefix(40))
            }
            return "Running command..."
        case "Edit":
            if let path = input["file_path"] {
                return "Edit: \(URL(fileURLWithPath: path).lastPathComponent)"
            }
            return "Editing..."
        case "Write":
            if let path = input["file_path"] {
                return "Write: \(URL(fileURLWithPath: path).lastPathComponent)"
            }
            return "Writing..."
        case "WebFetch":
            if let url = input["url"] {
                return "Fetching: \(url.prefix(30))..."
            }
            return "Fetching..."
        case "WebSearch":
            if let query = input["query"] {
                return "Search: \(query.prefix(30))"
            }
            return "Searching web..."
        default:
            return name
        }
    }
}
