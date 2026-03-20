//
//  SidebarView.swift
//  ClaudeIsland
//
//  Sidebar showing mode toggle, search, project groups and thread list.
//

import SwiftUI

struct SidebarView: View {
    @Bindable var viewModel: SidebarViewModel

    var body: some View {
        VStack(spacing: 0) {
            // Mode Picker
            modePickerSection

            // Action Buttons
            actionButtonsSection

            Divider()
                .padding(.horizontal)

            // Thread List
            threadListSection
        }
        .background(.ultraThinMaterial)
    }

    // MARK: - Mode Picker

    private var modePickerSection: some View {
        Picker("Mode", selection: $viewModel.mode) {
            ForEach(SidebarMode.allCases, id: \.self) { mode in
                Label(mode.rawValue, systemImage: mode.icon)
                    .tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    // MARK: - Action Buttons

    private var actionButtonsSection: some View {
        VStack(spacing: 6) {
            // Search
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 12))
                TextField("Search sessions...", text: $viewModel.searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))

                if !viewModel.searchText.isEmpty {
                    Button {
                        viewModel.searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(.quaternary.opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .padding(.horizontal, 12)

            // New Chat + Import (only in My Sessions mode)
            if viewModel.mode == .mySessions {
                HStack(spacing: 8) {
                    Button {
                        selectFolderAndCreateThread()
                    } label: {
                        Label("New Chat", systemImage: "plus.bubble")
                            .font(.system(size: 12, weight: .medium))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button {
                        viewModel.showImportSheet = true
                    } label: {
                        Label("Import", systemImage: "square.and.arrow.down")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .padding(.horizontal, 12)
            }
        }
        .padding(.bottom, 8)
    }

    // MARK: - Thread List

    private var threadListSection: some View {
        ScrollView {
            LazyVStack(spacing: 0, pinnedViews: .sectionHeaders) {
                switch viewModel.mode {
                case .mySessions:
                    mySessionsContent

                case .globalMonitor:
                    globalMonitorContent
                }
            }
            .padding(.top, 4)
        }
    }

    @ViewBuilder
    private var mySessionsContent: some View {
        if viewModel.projects.isEmpty && !viewModel.isLoading {
            emptyStateView(
                icon: "bubble.left.and.text.bubble.right",
                title: "No Sessions",
                subtitle: "Start a new chat or import from Claude CLI"
            )
        } else {
            ForEach(viewModel.projects) { group in
                Section {
                    ForEach(group.threads) { thread in
                        ThreadRowView(
                            thread: thread,
                            isSelected: viewModel.selectedThreadId == thread.id,
                            onSelect: { viewModel.selectedThreadId = thread.id },
                            onDelete: {
                                Task { await viewModel.deleteThread(id: thread.id) }
                            }
                        )
                    }
                } header: {
                    projectHeaderView(name: group.name, threadCount: group.threads.count)
                }
            }
        }
    }

    @ViewBuilder
    private var globalMonitorContent: some View {
        if !AppSettings.hookMonitorEnabled {
            emptyStateView(
                icon: "globe",
                title: "Hook Monitor Disabled",
                subtitle: "Enable in Settings to monitor all Claude Code sessions"
            )
        } else if viewModel.globalSessions.isEmpty {
            emptyStateView(
                icon: "antenna.radiowaves.left.and.right",
                title: "No Active Sessions",
                subtitle: "Start a Claude Code session in any terminal"
            )
        } else {
            ForEach(viewModel.globalSessions) { session in
                GlobalSessionRowView(
                    session: session,
                    onSelect: {
                        // TODO: Show session details in detail view
                    },
                    onTakeover: {
                        Task { _ = await viewModel.takeoverSession(session) }
                    }
                )
            }
        }
    }

    // MARK: - Helper Views

    private func projectHeaderView(name: String, threadCount: Int) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "folder.fill")
                .font(.system(size: 11))
                .foregroundStyle(.orange)
            Text(name)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.primary)
            Spacer()
            Text("\(threadCount)")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.quaternary)
                .clipShape(Capsule())
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(.bar)
    }

    private func emptyStateView(icon: String, title: String, subtitle: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 28))
                .foregroundStyle(.tertiary)
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
            Text(subtitle)
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    // MARK: - Folder Selection

    private func selectFolderAndCreateThread() {
        let panel = NSOpenPanel()
        panel.title = "Select Working Directory"
        panel.message = "Choose a project folder for the new Claude conversation"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = false
        panel.allowsMultipleSelection = false

        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            Task {
                _ = await viewModel.createNewThread(projectPath: url.path)
            }
        }
    }
}

// MARK: - Thread Row View

struct ThreadRowView: View {
    let thread: ThreadDTO
    let isSelected: Bool
    let onSelect: () -> Void
    let onDelete: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 8) {
                // Status indicator
                Circle()
                    .fill(statusColor)
                    .frame(width: 7, height: 7)

                VStack(alignment: .leading, spacing: 2) {
                    // Title
                    Text(thread.title ?? "New Chat")
                        .font(.system(size: 13))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    HStack(spacing: 4) {
                        // Git branch badge
                        if let branch = thread.gitBranch {
                            HStack(spacing: 2) {
                                Image(systemName: "arrow.triangle.branch")
                                    .font(.system(size: 8))
                                Text(branch)
                                    .font(.system(size: 10))
                            }
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        }

                        // Source badge
                        if thread.source != .app {
                            Text(thread.source == .imported ? "imported" : "takeover")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(thread.source == .imported ? .blue : .green)
                                .clipShape(Capsule())
                        }
                    }
                }

                Spacer()

                // Time
                Text(thread.updatedAt.relativeFormatted)
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private var statusColor: Color {
        switch thread.status {
        case .active: return .green
        case .idle: return .gray
        case .ended: return .gray.opacity(0.5)
        }
    }
}

// MARK: - Global Session Row View

struct GlobalSessionRowView: View {
    let session: HookSessionInfo
    let onSelect: () -> Void
    let onTakeover: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 8) {
                // Status indicator
                Circle()
                    .fill(globalStatusColor)
                    .frame(width: 7, height: 7)

                VStack(alignment: .leading, spacing: 2) {
                    Text(session.title ?? session.projectName)
                        .font(.system(size: 13))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    HStack(spacing: 4) {
                        Text(session.projectName)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)

                        Text("•")
                            .font(.system(size: 8))
                            .foregroundStyle(.quaternary)

                        Text("\(session.messageCount) msgs")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                // Takeover button (only when session is idle)
                if session.status == "waitingForInput" || session.status == "ended" {
                    Button {
                        onTakeover()
                    } label: {
                        Label("Continue", systemImage: "play.fill")
                            .font(.system(size: 10))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                }

                // Status badge
                Text(session.status)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(globalStatusColor.opacity(0.9))
                    .clipShape(Capsule())
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var globalStatusColor: Color {
        switch session.status {
        case "processing": return .orange
        case "waitingForInput": return .blue
        case "waitingForApproval": return .red
        case "ended": return .gray
        default: return .gray
        }
    }
}

// MARK: - Date Extension

extension Date {
    var relativeFormatted: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: self, relativeTo: Date())
    }
}
