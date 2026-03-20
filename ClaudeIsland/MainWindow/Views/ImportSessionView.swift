//
//  ImportSessionView.swift
//  ClaudeIsland
//
//  Modal dialog for importing sessions from Claude CLI.
//  Scans ~/.claude/projects/ and shows importable sessions.
//

import SwiftUI
import SwiftData

struct ImportSessionView: View {
    @Environment(\.dismiss) private var dismiss
    let onImportComplete: () -> Void

    @State private var sessions: [ImportableSession] = []
    @State private var selectedIds: Set<String> = []
    @State private var searchText = ""
    @State private var isScanning = true
    @State private var isImporting = false
    @State private var importedCount = 0
    @State private var alreadyImportedIds: Set<String> = []

    var body: some View {
        VStack(spacing: 0) {
            // Header
            header

            Divider()

            // Search
            searchBar

            // Session list
            sessionList

            Divider()

            // Footer
            footer
        }
        .frame(width: 640, height: 520)
        .task {
            await scanSessions()
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Import from Claude CLI")
                    .font(.system(size: 16, weight: .bold))
                Text("Select sessions to import from ~/.claude/projects/")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(16)
    }

    // MARK: - Search

    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .font(.system(size: 12))
            TextField("Search by project or message...", text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(.quaternary.opacity(0.3))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    // MARK: - Session List

    private var sessionList: some View {
        ScrollView {
            if isScanning {
                VStack(spacing: 8) {
                    ProgressView()
                    Text("Scanning Claude CLI sessions...")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 40)
            } else if filteredSessions.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 28))
                        .foregroundStyle(.tertiary)
                    Text("No sessions found")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 40)
            } else {
                LazyVStack(spacing: 4) {
                    ForEach(filteredSessions) { session in
                        importableSessionRow(session)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
            }
        }
    }

    private func importableSessionRow(_ session: ImportableSession) -> some View {
        let isAlreadyImported = alreadyImportedIds.contains(session.id)
        let isSelected = selectedIds.contains(session.id)

        return Button {
            if !isAlreadyImported {
                if isSelected {
                    selectedIds.remove(session.id)
                } else {
                    selectedIds.insert(session.id)
                }
            }
        } label: {
            HStack(spacing: 10) {
                // Checkbox
                Image(systemName: isAlreadyImported
                    ? "checkmark.circle.fill"
                    : isSelected ? "checkmark.circle.fill" : "circle"
                )
                .font(.system(size: 16))
                .foregroundStyle(isAlreadyImported ? .green : isSelected ? .accentColor : .secondary)

                // Info
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        // Project name
                        Text(session.projectName)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.primary)

                        // Git branch
                        if let branch = session.gitBranch {
                            HStack(spacing: 2) {
                                Image(systemName: "arrow.triangle.branch")
                                    .font(.system(size: 8))
                                Text(branch)
                                    .font(.system(size: 10))
                            }
                            .foregroundStyle(.purple)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(.purple.opacity(0.1))
                            .clipShape(Capsule())
                        }

                        // Already imported badge
                        if isAlreadyImported {
                            Text("Imported")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(.green)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(.green.opacity(0.1))
                                .clipShape(Capsule())
                        }
                    }

                    // First message
                    Text(session.firstMessage)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    // Metadata
                    HStack(spacing: 8) {
                        Label("\(session.messageCount) msgs", systemImage: "text.bubble")
                        Label(session.fileSize.formattedFileSize, systemImage: "doc")
                        Label(session.lastModified.relativeFormatted, systemImage: "clock")

                        if let version = session.claudeVersion {
                            Label("v\(version)", systemImage: "cpu")
                        }
                    }
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                }

                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(isSelected ? Color.accentColor.opacity(0.08) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isAlreadyImported)
        .opacity(isAlreadyImported ? 0.6 : 1)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Text("\(filteredSessions.count) sessions found")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            if importedCount > 0 {
                Text("• \(importedCount) imported")
                    .font(.system(size: 11))
                    .foregroundStyle(.green)
            }

            Spacer()

            Button("Cancel") {
                dismiss()
            }
            .keyboardShortcut(.cancelAction)

            Button {
                Task { await importSelected() }
            } label: {
                if isImporting {
                    ProgressView()
                        .controlSize(.small)
                        .padding(.horizontal, 8)
                } else {
                    Text("Import \(selectedIds.count) Session\(selectedIds.count == 1 ? "" : "s")")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(selectedIds.isEmpty || isImporting)
            .keyboardShortcut(.defaultAction)
        }
        .padding(16)
    }

    // MARK: - Filtering

    private var filteredSessions: [ImportableSession] {
        guard !searchText.isEmpty else { return sessions }
        let query = searchText.lowercased()
        return sessions.filter {
            $0.projectName.lowercased().contains(query) ||
            $0.firstMessage.lowercased().contains(query) ||
            ($0.gitBranch?.lowercased().contains(query) ?? false)
        }
    }

    // MARK: - Actions

    private func scanSessions() async {
        isScanning = true
        sessions = await CLISessionScanner.scan()

        // Check which are already imported
        let actor = BackgroundDataActor(modelContainer: DataStore.shared)
        var imported: Set<String> = []
        for session in sessions {
            if let isImported = try? await actor.isImported(cliSessionId: session.id), isImported {
                imported.insert(session.id)
            }
        }
        alreadyImportedIds = imported

        isScanning = false
    }

    private func importSelected() async {
        isImporting = true
        let actor = BackgroundDataActor(modelContainer: DataStore.shared)

        for sessionId in selectedIds {
            guard let session = sessions.first(where: { $0.id == sessionId }) else { continue }

            do {
                let projectId = try await actor.findOrCreateProject(path: session.projectPath)
                let threadId = try await actor.createThread(
                    projectId: projectId,
                    title: session.firstMessage,
                    source: .imported,
                    cliSessionId: session.id,
                    gitBranch: session.gitBranch
                )
                try await actor.recordImport(cliSessionId: session.id, threadId: threadId)

                alreadyImportedIds.insert(session.id)
                importedCount += 1
            } catch {
                // Continue with other imports
            }
        }

        selectedIds.removeAll()
        isImporting = false
        onImportComplete()
    }
}

// MARK: - File Size Formatting

extension Int64 {
    var formattedFileSize: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: self)
    }
}
