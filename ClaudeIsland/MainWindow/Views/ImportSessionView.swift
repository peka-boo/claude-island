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
    @State private var selectedProject: String?
    @State private var isScanning = true
    @State private var isImporting = false
    @State private var importedCount = 0
    @State private var alreadyImportedIds: Set<String> = []

    var body: some View {
        ZStack {
            MainWindowBackdrop()

            VStack(spacing: 14) {
                header
                filterControls
                sessionList
                footer
            }
            .padding(18)
        }
        .frame(width: 760, height: 620)
        .preferredColorScheme(.dark)
        .task {
            await scanSessions()
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Import Claude Sessions")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(MainWindowTheme.textPrimary)
                Text("Restore conversations discovered under ~/.claude/projects/")
                    .font(.system(size: 12))
                    .foregroundStyle(MainWindowTheme.textSecondary)
            }
            Spacer()
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(MainWindowTheme.textSecondary)
                    .frame(width: 30, height: 30)
                    .background(MainWindowTheme.panelElevated)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(20)
        .mainWindowCard(
            fill: Color.black.opacity(0.18),
            border: MainWindowTheme.borderStrong,
            radius: 24
        )
    }

    // MARK: - Search

    private var filterControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(MainWindowTheme.textMuted)
                    .font(.system(size: 12))
                TextField("Search by project or message...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundStyle(MainWindowTheme.textPrimary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)

            if !sessions.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(projectFilters) { filter in
                            projectFilterChip(filter)
                        }
                    }
                    .padding(.horizontal, 2)
                    .padding(.vertical, 2)
                }
            }
        }
        .mainWindowCard(
            fill: MainWindowTheme.panelElevated,
            border: MainWindowTheme.borderStrong,
            radius: 18,
            shadowOpacity: 0
        )
    }

    private func projectFilterChip(_ filter: ImportSessionProjectFilter) -> some View {
        let isSelected = selectedProject == filter.selectedProjectName

        return Button {
            selectedProject = filter.selectedProjectName
        } label: {
            HStack(spacing: 6) {
                Text(filter.title)
                    .font(.system(size: 11, weight: .semibold))
                Text("\(filter.count)")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(isSelected ? Color.black.opacity(0.72) : MainWindowTheme.textMuted)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(
                        Capsule()
                            .fill(isSelected ? Color.black.opacity(0.10) : Color.white.opacity(0.08))
                    )
            }
            .foregroundStyle(isSelected ? Color.black : MainWindowTheme.textSecondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(
                Capsule()
                    .fill(isSelected ? Color.white.opacity(0.94) : MainWindowTheme.panel)
                    .overlay(
                        Capsule()
                            .strokeBorder(isSelected ? Color.white.opacity(0.24) : MainWindowTheme.border, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Session List

    private var sessionList: some View {
        ScrollView {
            if isScanning {
                VStack(spacing: 10) {
                    ProgressView()
                    Text("Scanning Claude CLI sessions...")
                        .font(.system(size: 12))
                        .foregroundStyle(MainWindowTheme.textSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 56)
            } else if filteredSessions.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 28))
                        .foregroundStyle(MainWindowTheme.textMuted)
                    Text("No importable sessions found")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(MainWindowTheme.textPrimary)
                    Text("Try a different search or start a new Claude conversation in the terminal first.")
                        .font(.system(size: 11))
                        .foregroundStyle(MainWindowTheme.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 56)
            } else {
                LazyVStack(spacing: 10) {
                    ForEach(filteredSessions) { session in
                        importableSessionRow(session)
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .padding(16)
        .mainWindowCard(
            fill: Color.black.opacity(0.18),
            border: MainWindowTheme.borderStrong,
            radius: 24
        )
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
            HStack(spacing: 12) {
                // Checkbox
                Image(systemName: isAlreadyImported
                    ? "checkmark.circle.fill"
                    : isSelected ? "checkmark.circle.fill" : "circle"
                )
                .font(.system(size: 16))
                .foregroundStyle(isAlreadyImported ? TerminalColors.green : isSelected ? MainWindowTheme.accent : MainWindowTheme.textMuted)

                // Info
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        // Project name
                        Text(session.projectName)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(MainWindowTheme.textPrimary)

                        // Git branch
                        if let branch = session.gitBranch {
                            importChip(branch, icon: "arrow.triangle.branch", fill: TerminalColors.blue.opacity(0.18))
                        }

                        // Already imported badge
                        if isAlreadyImported {
                            importChip("Imported", icon: "checkmark", fill: TerminalColors.green.opacity(0.18))
                        }
                    }

                    // First message
                    Text(session.firstMessage)
                        .font(.system(size: 12))
                        .foregroundStyle(MainWindowTheme.textSecondary)
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
                    .foregroundStyle(MainWindowTheme.textMuted)
                }

                Spacer()
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(isSelected ? MainWindowTheme.panelSelected : MainWindowTheme.panel)
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(isSelected ? MainWindowTheme.borderStrong : MainWindowTheme.border, lineWidth: 1)
                    )
            )
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
                .foregroundStyle(MainWindowTheme.textSecondary)

            if importedCount > 0 {
                Text("• \(importedCount) imported")
                    .font(.system(size: 11))
                    .foregroundStyle(TerminalColors.green)
            }

            Spacer()

            Button("Cancel") {
                dismiss()
            }
            .buttonStyle(.plain)
            .foregroundStyle(MainWindowTheme.textSecondary)
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
            .buttonStyle(.plain)
            .foregroundStyle(selectedIds.isEmpty || isImporting ? MainWindowTheme.textMuted : .black)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background((selectedIds.isEmpty || isImporting ? MainWindowTheme.panelElevated : Color.white.opacity(0.95)))
            .clipShape(Capsule())
            .disabled(selectedIds.isEmpty || isImporting)
            .keyboardShortcut(.defaultAction)
        }
        .padding(18)
        .mainWindowCard(
            fill: Color.black.opacity(0.18),
            border: MainWindowTheme.borderStrong,
            radius: 24
        )
    }

    private func importChip(_ label: String, icon: String, fill: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .medium))
            Text(label)
                .font(.system(size: 10, weight: .medium))
        }
        .foregroundStyle(MainWindowTheme.textSecondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(fill)
        .clipShape(Capsule())
    }

    // MARK: - Filtering

    private var filteredSessions: [ImportableSession] {
        ImportSessionFilterSupport.filteredSessions(
            sessions,
            searchText: searchText,
            selectedProject: selectedProject
        )
    }

    private var projectFilters: [ImportSessionProjectFilter] {
        ImportSessionFilterSupport.projectFilters(from: sessions)
    }

    // MARK: - Actions

    private func scanSessions() async {
        isScanning = true
        sessions = await CLISessionScanner.scan()
        if let selectedProject,
           sessions.contains(where: { $0.projectName == selectedProject }) == false {
            self.selectedProject = nil
        }

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
                let history = try ImportedSessionHistoryParser.parse(
                    jsonlURL: URL(fileURLWithPath: session.jsonlPath)
                )
                let projectId = try await actor.findOrCreateProject(path: session.projectPath)
                let threadId = try await actor.createThread(
                    projectId: projectId,
                    title: history.firstMessage,
                    source: .imported,
                    cliSessionId: session.id,
                    gitBranch: session.gitBranch,
                    createdAt: history.createdAt ?? session.lastModified,
                    updatedAt: history.updatedAt ?? session.lastModified
                )

                for record in history.messageRecords {
                    try await actor.appendMessage(
                        threadId: threadId,
                        role: messageRole(for: record.role),
                        content: record.content,
                        thinking: record.thinking,
                        toolName: record.toolName,
                        toolInput: record.toolInput,
                        toolResult: record.toolResult,
                        createdAt: record.createdAt
                    )
                }

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

    private func messageRole(for importedRole: ImportedSessionMessageRole) -> MessageRole {
        switch importedRole {
        case .user: return .user
        case .assistant: return .assistant
        case .system: return .system
        }
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
