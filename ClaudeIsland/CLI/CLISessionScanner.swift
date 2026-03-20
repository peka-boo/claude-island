//
//  CLISessionScanner.swift
//  ClaudeIsland
//
//  Scans ~/.claude/projects/ to discover importable CLI sessions.
//

import Foundation
import os.log

private let logger = Logger(subsystem: "com.claudeisland", category: "Scanner")

// MARK: - Importable Session

struct ImportableSession: Identifiable, Sendable {
    let id: String           // JSONL filename (acts as session identifier)
    let projectPath: String  // Original project path
    let projectName: String  // Project folder name
    let jsonlPath: String    // Full path to JSONL file
    let firstMessage: String // First user message (summary)
    let messageCount: Int    // Approximate message count
    let fileSize: Int64      // File size in bytes
    let lastModified: Date   // Last modification date
    let gitBranch: String?   // Git branch (if detectable)
    let claudeVersion: String? // Claude Code version
}

// MARK: - CLISessionScanner

enum CLISessionScanner {

    private static let claudeProjectsDir: URL = {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/projects")
    }()

    /// Scan all Claude CLI projects and return importable sessions.
    static func scan() async -> [ImportableSession] {
        let fm = FileManager.default

        guard let projectDirs = try? fm.contentsOfDirectory(
            at: claudeProjectsDir,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: .skipsHiddenFiles
        ) else {
            logger.info("No Claude projects directory found")
            return []
        }

        var sessions: [ImportableSession] = []

        for projectDir in projectDirs {
            guard let isDir = try? projectDir.resourceValues(forKeys: [.isDirectoryKey]).isDirectory,
                  isDir else { continue }

            // Decode project path from directory name
            // e.g., "-Users-mac-Code-GITHUB---claude-island" -> "/Users/mac/Code/GITHUB/--/claude-island"
            let projectPath = decodeProjectPath(projectDir.lastPathComponent)
            let projectName = URL(fileURLWithPath: projectPath).lastPathComponent

            // Find JSONL session files
            guard let files = try? fm.contentsOfDirectory(
                at: projectDir,
                includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
                options: .skipsHiddenFiles
            ) else { continue }

            for file in files where file.pathExtension == "jsonl" && !file.lastPathComponent.hasPrefix("agent-") {
                guard let attrs = try? file.resourceValues(forKeys: [
                    .contentModificationDateKey, .fileSizeKey
                ]) else { continue }

                let fileSize = attrs.fileSize ?? 0
                let lastModified = attrs.contentModificationDate ?? Date.distantPast

                // Extract metadata from first few lines
                let metadata = extractMetadata(from: file)

                let session = ImportableSession(
                    id: file.lastPathComponent,
                    projectPath: projectPath,
                    projectName: projectName,
                    jsonlPath: file.path,
                    firstMessage: metadata.firstMessage,
                    messageCount: metadata.messageCount,
                    fileSize: Int64(fileSize),
                    lastModified: lastModified,
                    gitBranch: metadata.gitBranch,
                    claudeVersion: metadata.version
                )
                sessions.append(session)
            }
        }

        // Sort by last modified (newest first)
        return sessions.sorted { $0.lastModified > $1.lastModified }
    }

    // MARK: - Path Decoding

    /// Decode the encoded project directory name back to a path.
    /// "-Users-mac-Code" -> "/Users/mac/Code"
    private static func decodeProjectPath(_ encodedName: String) -> String {
        "/" + encodedName.replacingOccurrences(of: "-", with: "/")
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    // MARK: - Metadata Extraction

    private struct SessionMetadata {
        var firstMessage: String = "No messages"
        var messageCount: Int = 0
        var gitBranch: String?
        var version: String?
    }

    /// Extract metadata from the beginning and end of a JSONL file.
    private static func extractMetadata(from url: URL) -> SessionMetadata {
        var meta = SessionMetadata()

        guard let handle = FileHandle(forReadingAtPath: url.path) else { return meta }
        defer { try? handle.close() }

        // Read first 16KB for metadata
        let headData = handle.readData(ofLength: 16384)
        guard let headContent = String(data: headData, encoding: .utf8) else { return meta }

        let lines = headContent.components(separatedBy: .newlines)
        var lineCount = 0

        for line in lines where !line.isEmpty {
            lineCount += 1
            guard let data = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                continue
            }

            // Version
            if meta.version == nil, let version = json["version"] as? String {
                meta.version = version
            }

            // First user message
            if meta.firstMessage == "No messages",
               let type = json["type"] as? String, type == "human",
               let message = json["message"] as? [String: Any],
               let content = message["content"] as? [[String: Any]] {
                for block in content {
                    if let text = block["text"] as? String, !text.isEmpty {
                        let maxLen = 80
                        meta.firstMessage = text.count > maxLen
                            ? String(text.prefix(maxLen)) + "..."
                            : text
                        break
                    }
                }
            }

            // Git branch (from cwd or metadata)
            if meta.gitBranch == nil, let cwd = json["cwd"] as? String {
                meta.gitBranch = detectGitBranch(at: cwd)
            }
        }

        // Estimate total message count from file size
        // Average JSONL line is ~2KB for assistant responses
        if let fileSize = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize {
            meta.messageCount = max(lineCount, fileSize / 2000)
        } else {
            meta.messageCount = lineCount
        }

        return meta
    }

    private static func detectGitBranch(at path: String) -> String? {
        let headPath = URL(fileURLWithPath: path)
            .appendingPathComponent(".git/HEAD")
        guard let content = try? String(contentsOf: headPath, encoding: .utf8) else {
            return nil
        }
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("ref: refs/heads/") {
            return String(trimmed.dropFirst("ref: refs/heads/".count))
        }
        return nil
    }
}
