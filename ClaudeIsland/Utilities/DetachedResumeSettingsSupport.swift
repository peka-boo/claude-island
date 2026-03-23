//
//  DetachedResumeSettingsSupport.swift
//  ClaudeIsland
//
//  Builds hook-free Claude settings for app-launched detached resume turns.
//

import Foundation

enum DetachedResumeSettingsSupport {
    nonisolated private static let userSettingsRelativePaths = [
        ".claude/settings.json",
        ".claude/settings.local.json",
    ]

    nonisolated private static let projectSettingsRelativePaths = [
        ".claude/settings.json",
        ".claude/settings.local.json",
    ]

    nonisolated static func sanitizedSettings(
        cwd: String,
        homeDirectory: URL? = nil,
        fileManager: FileManager? = nil
    ) throws -> [String: Any] {
        let fileManager = fileManager ?? .default
        let homeDirectory = homeDirectory ?? fileManager.homeDirectoryForCurrentUser
        var merged: [String: Any] = [:]

        for relativePath in userSettingsRelativePaths {
            let fileURL = homeDirectory.appendingPathComponent(relativePath)
            merge(
                try readSettingsFile(at: fileURL, fileManager: fileManager),
                into: &merged
            )
        }

        let cwdURL = URL(fileURLWithPath: cwd, isDirectory: true)
        for relativePath in projectSettingsRelativePaths {
            let fileURL = cwdURL.appendingPathComponent(relativePath)
            merge(
                try readSettingsFile(at: fileURL, fileManager: fileManager),
                into: &merged
            )
        }

        merged.removeValue(forKey: "hooks")
        return merged
    }

    nonisolated static func writeSanitizedSettingsFile(
        cwd: String,
        homeDirectory: URL? = nil,
        fileManager: FileManager? = nil
    ) throws -> URL {
        let fileManager = fileManager ?? .default
        let settings = try sanitizedSettings(
            cwd: cwd,
            homeDirectory: homeDirectory,
            fileManager: fileManager
        )

        let directoryURL = fileManager.temporaryDirectory
            .appendingPathComponent("claude-island-detached-settings", isDirectory: true)
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        let fileURL = directoryURL.appendingPathComponent("\(UUID().uuidString).json")
        let data = try JSONSerialization.data(
            withJSONObject: settings,
            options: [.sortedKeys]
        )

        try data.write(to: fileURL, options: .atomic)
        try fileManager.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: fileURL.path
        )

        return fileURL
    }

    nonisolated static func removeSanitizedSettingsFile(
        at fileURL: URL?,
        fileManager: FileManager? = nil
    ) {
        let fileManager = fileManager ?? .default
        guard let fileURL else { return }
        try? fileManager.removeItem(at: fileURL)
    }

    nonisolated private static func readSettingsFile(
        at fileURL: URL,
        fileManager: FileManager
    ) throws -> [String: Any] {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return [:]
        }

        let data = try Data(contentsOf: fileURL)
        guard !data.isEmpty else {
            return [:]
        }

        let object = try JSONSerialization.jsonObject(with: data)
        return object as? [String: Any] ?? [:]
    }

    nonisolated private static func merge(_ next: [String: Any], into current: inout [String: Any]) {
        for (key, value) in next {
            if let nextDictionary = value as? [String: Any],
               let currentDictionary = current[key] as? [String: Any] {
                var mergedDictionary = currentDictionary
                merge(nextDictionary, into: &mergedDictionary)
                current[key] = mergedDictionary
            } else {
                current[key] = value
            }
        }
    }
}
