//
//  SidebarView.swift
//  ClaudeIsland
//
//  Screenshot-inspired sidebar with icon rail and compact thread list.
//

import SwiftUI

struct SidebarView: View {
    @Bindable var viewModel: SidebarViewModel
    @ObservedObject private var sessionMonitor = ClaudeSessionMonitor.shared
    @State private var hasAppeared = false
    @State private var showClaudeHookMenu = false
    @Namespace private var selectionNamespace

    var body: some View {
        ZStack(alignment: .topLeading) {
            HStack(spacing: 0) {
                iconRail
                    .frame(width: MainWindowTheme.scaled(76))
                    .frame(maxHeight: .infinity)
                    .background(MainWindowTheme.sidebarRail)

                conversationPanel
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .background(MainWindowTheme.sidebarPanel)
            }

            if showClaudeHookMenu {
                ClaudeHookMenuCard {
                    withAnimation(MainWindowTheme.panelCloseAnimation) {
                        showClaudeHookMenu = false
                    }
                }
                .frame(width: MainWindowTheme.scaled(272))
                .offset(
                    x: MainWindowTheme.scaled(76) + MainWindowTheme.scaled(18),
                    y: claudeHookPanelOffsetY
                )
                .transition(
                    .opacity
                        .combined(with: .move(edge: .leading))
                        .combined(with: .scale(scale: 0.98, anchor: .leading))
                )
                .zIndex(2)
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            withAnimation(MainWindowTheme.entranceAnimation) {
                hasAppeared = true
            }
            viewModel.updateLiveMonitorSessions(sessionMonitor.instances)
        }
        .onChange(of: sessionMonitor.instances) { _, sessions in
            viewModel.updateLiveMonitorSessions(sessions)
        }
        .onChange(of: viewModel.mode) { _, newMode in
            guard newMode == .globalMonitor else { return }
            Task { await viewModel.refreshGlobalSessions() }
        }
    }

    private var iconRail: some View {
        VStack(spacing: 18) {
            SidebarRailBadge()
                .padding(.top, 22)

            SidebarRailButton(
                icon: "bubble.left.fill",
                isSelected: viewModel.mode == .mySessions
            ) {
                showClaudeHookMenu = false
                withAnimation(MainWindowTheme.selectionAnimation) {
                    viewModel.mode = .mySessions
                }
            }

            SidebarRailButton(
                icon: "wave.3.right",
                isSelected: viewModel.mode == .globalMonitor
            ) {
                showClaudeHookMenu = false
                withAnimation(MainWindowTheme.selectionAnimation) {
                    viewModel.mode = .globalMonitor
                }
            }

            SidebarRailButton(icon: "square.and.arrow.down", isSelected: false) {
                showClaudeHookMenu = false
                viewModel.showImportSheet = true
            }

            SidebarRailButton(icon: "gearshape.fill", isSelected: showClaudeHookMenu) {
                withAnimation(MainWindowTheme.panelOpenAnimation) {
                    showClaudeHookMenu.toggle()
                }
            }

            Spacer()

            Text("v0.38.3")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(MainWindowTheme.textMuted)
                .padding(.bottom, 16)
        }
        .padding(.horizontal, 10)
        .revealTransition(show: hasAppeared, x: -8, y: 0)
    }

    private var conversationPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                HStack(spacing: 8) {
                    Circle()
                        .fill(TerminalColors.green)
                        .frame(width: MainWindowTheme.scaled(8), height: MainWindowTheme.scaled(8))

                    Text("Connected")
                        .font(.system(size: MainWindowTheme.scaled(15), weight: .semibold))
                        .foregroundStyle(TerminalColors.green)
                }
                .padding(.horizontal, MainWindowTheme.scaled(14))
                .padding(.vertical, MainWindowTheme.scaled(10))
                .background(TerminalColors.green.opacity(0.10))
                .clipShape(Capsule())

                Spacer()
            }
            .padding(.horizontal, MainWindowTheme.scaled(22))
            .padding(.top, MainWindowTheme.scaled(20))
            .padding(.bottom, MainWindowTheme.scaled(18))

            if viewModel.mode == .mySessions {
                HStack(spacing: MainWindowTheme.scaled(10)) {
                    SidebarPrimaryButton(
                        title: "New Conversation",
                        systemImage: "plus"
                    ) {
                        selectFolderAndCreateThread()
                    }

                    SidebarSquareButton(systemImage: "folder") {
                        viewModel.showImportSheet = true
                    }
                }
                .padding(.horizontal, MainWindowTheme.scaled(22))
                .padding(.bottom, MainWindowTheme.scaled(14))
                .revealTransition(show: hasAppeared, y: 6)
            }

            searchBar
                .padding(.horizontal, MainWindowTheme.scaled(22))
                .padding(.bottom, MainWindowTheme.scaled(12))

            if viewModel.mode == .mySessions {
                SidebarLineRow(
                    icon: "doc.badge.plus",
                    title: "Import from Claude Code"
                ) {
                    viewModel.showImportSheet = true
                }
                .padding(.horizontal, MainWindowTheme.scaled(22))
                .padding(.bottom, MainWindowTheme.scaled(22))
            }

            Text(viewModel.mode == .mySessions ? "THREADS" : "GLOBAL MONITOR")
                .font(.system(size: MainWindowTheme.scaled(12), weight: .semibold))
                .tracking(1.4)
                .foregroundStyle(MainWindowTheme.textMuted)
                .padding(.horizontal, MainWindowTheme.scaled(22))
                .padding(.bottom, MainWindowTheme.scaled(12))

            ScrollView {
                LazyVStack(alignment: .leading, spacing: MainWindowTheme.scaled(8), pinnedViews: .sectionHeaders) {
                    switch viewModel.mode {
                    case .mySessions:
                        mySessionsContent
                    case .globalMonitor:
                        globalMonitorContent
                    }
                }
                .padding(.horizontal, MainWindowTheme.scaled(12))
                .padding(.bottom, MainWindowTheme.scaled(20))
            }
            .scrollIndicators(.never)
        }
    }

    @ViewBuilder
    private var mySessionsContent: some View {
        if viewModel.projects.isEmpty && !viewModel.isLoading {
            sidebarEmptyState(
                icon: "bubble.left.and.text.bubble.right",
                title: "No threads yet",
                subtitle: "Create a new conversation or import one from Claude Code."
            )
        } else {
            ForEach(viewModel.projects) { group in
                Section {
                    if !viewModel.isProjectCollapsed(group.id) {
                        VStack(alignment: .leading, spacing: MainWindowTheme.scaled(1)) {
                            ForEach(group.threads) { thread in
                                ThreadRowView(
                                    title: viewModel.displayTitle(for: thread),
                                    gitBranch: viewModel.displayGitBranch(for: thread),
                                    lastEventAt: viewModel.displayLastEventAt(for: thread),
                                    status: viewModel.displayStatus(for: thread),
                                    isSelected: viewModel.isSelected(thread),
                                    selectionNamespace: selectionNamespace,
                                    onSelect: { viewModel.selectThread(thread) },
                                    onDelete: { Task { await viewModel.deleteThread(id: thread.id) } }
                                )
                            }
                        }
                        .padding(.leading, MainWindowTheme.scaled(24))
                        .overlay(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 999, style: .continuous)
                                .fill(MainWindowTheme.separator.opacity(0.9))
                                .frame(width: 1)
                                .padding(.vertical, MainWindowTheme.scaled(8))
                                .offset(x: MainWindowTheme.scaled(11))
                        }
                        .transition(MainWindowTheme.sectionRevealTransition)
                    }
                } header: {
                    SidebarProjectHeader(
                        name: group.name,
                        isCollapsed: viewModel.isProjectCollapsed(group.id)
                    ) {
                        withAnimation(MainWindowTheme.panelOpenAnimation) {
                            viewModel.toggleProjectCollapse(group.id)
                        }
                    }
                        .padding(.leading, 10)
                        .padding(.bottom, MainWindowTheme.scaled(5))
                        .padding(.top, group.id == viewModel.projects.first?.id ? 0 : MainWindowTheme.scaled(6))
                        .background(MainWindowTheme.sidebarPanel)
                }
            }
        }
    }

    @ViewBuilder
    private var globalMonitorContent: some View {
        if viewModel.globalSessions.isEmpty {
            sidebarEmptyState(
                icon: "terminal",
                title: "No Claude sessions found",
                subtitle: AppSettings.hookMonitorEnabled
                    ? "Start Claude in a terminal or open saved CLI sessions and they will appear here."
                    : "Live monitoring is off. Saved Claude CLI sessions will still appear here after they exist on disk."
            )
        } else {
            VStack(alignment: .leading, spacing: MainWindowTheme.scaled(8)) {
                if !AppSettings.hookMonitorEnabled {
                    Text("Live monitor is off. Showing saved Claude sessions from disk.")
                        .font(.system(size: MainWindowTheme.scaled(10), weight: .medium))
                        .foregroundStyle(MainWindowTheme.textMuted)
                        .padding(.horizontal, MainWindowTheme.scaled(14))
                        .padding(.bottom, MainWindowTheme.scaled(2))
                }

                ForEach(viewModel.globalSessionGroups) { group in
                    Section {
                        if !viewModel.isProjectCollapsed(group.id) {
                            VStack(alignment: .leading, spacing: MainWindowTheme.scaled(1)) {
                                ForEach(group.sessions) { session in
                                    GlobalSessionRowView(
                                        session: session,
                                        status: viewModel.displayStatus(for: session),
                                        isSelected: viewModel.isSelected(session),
                                        selectionNamespace: selectionNamespace,
                                        onSelect: {
                                            Task { _ = await viewModel.openGlobalSession(session) }
                                        }
                                    )
                                }
                            }
                            .padding(.leading, MainWindowTheme.scaled(24))
                            .overlay(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 999, style: .continuous)
                                    .fill(MainWindowTheme.separator.opacity(0.9))
                                    .frame(width: 1)
                                    .padding(.vertical, MainWindowTheme.scaled(8))
                                    .offset(x: MainWindowTheme.scaled(11))
                            }
                            .transition(MainWindowTheme.sectionRevealTransition)
                        }
                    } header: {
                        SidebarProjectHeader(
                            name: group.name,
                            isCollapsed: viewModel.isProjectCollapsed(group.id)
                        ) {
                            withAnimation(MainWindowTheme.panelOpenAnimation) {
                                viewModel.toggleProjectCollapse(group.id)
                            }
                        }
                        .padding(.leading, 10)
                        .padding(.bottom, MainWindowTheme.scaled(5))
                        .padding(.top, group.id == viewModel.globalSessionGroups.first?.id ? 0 : MainWindowTheme.scaled(6))
                        .background(MainWindowTheme.sidebarPanel)
                    }
                }
            }
        }
    }

    private func sidebarEmptyState(icon: String, title: String, subtitle: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 24, weight: .light))
                .foregroundStyle(MainWindowTheme.textMuted)

            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(MainWindowTheme.textPrimary)

            Text(subtitle)
                .font(.system(size: 11))
                .foregroundStyle(MainWindowTheme.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 220)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 52)
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: MainWindowTheme.scaled(13)))
                .foregroundStyle(MainWindowTheme.textMuted)

            TextField("Search sessions...", text: $viewModel.searchText)
                .textFieldStyle(.plain)
                .font(.system(size: MainWindowTheme.scaled(13)))
                .foregroundStyle(MainWindowTheme.textPrimary)

            if !viewModel.searchText.isEmpty {
                Button {
                    viewModel.searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: MainWindowTheme.scaled(12)))
                        .foregroundStyle(MainWindowTheme.textMuted)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, MainWindowTheme.scaled(14))
        .padding(.vertical, MainWindowTheme.scaled(13))
        .background(
            RoundedRectangle(cornerRadius: MainWindowTheme.scaled(16), style: .continuous)
                .fill(Color.white.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: MainWindowTheme.scaled(16), style: .continuous)
                        .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
                )
        )
        .revealTransition(show: hasAppeared, y: 6)
    }

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

    private var claudeHookPanelOffsetY: CGFloat {
        22
        + MainWindowTheme.scaled(52)
        + 18
        + MainWindowTheme.scaled(44)
        + 18
        + MainWindowTheme.scaled(44)
        + 18
        + MainWindowTheme.scaled(44)
        + 4
    }
}

private struct SidebarRailBadge: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.06))
                .frame(width: MainWindowTheme.scaled(52), height: MainWindowTheme.scaled(52))
            Image(systemName: "bubble.left.fill")
                .font(.system(size: MainWindowTheme.scaled(20), weight: .semibold))
                .foregroundStyle(.white)
        }
    }
}

private struct SidebarRailButton: View {
    let icon: String
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: MainWindowTheme.scaled(18), weight: .medium))
                .foregroundStyle(isSelected ? .white : MainWindowTheme.textSecondary)
                .frame(width: MainWindowTheme.scaled(44), height: MainWindowTheme.scaled(44))
                .background(
                    RoundedRectangle(cornerRadius: MainWindowTheme.scaled(14), style: .continuous)
                        .fill(isSelected ? Color.white.opacity(0.10) : (isHovered ? MainWindowTheme.hoverFill : Color.clear))
                        .overlay(
                            RoundedRectangle(cornerRadius: MainWindowTheme.scaled(14), style: .continuous)
                                .strokeBorder(isSelected ? Color.white.opacity(0.10) : Color.clear, lineWidth: 1)
                        )
                        .shadow(
                            color: isSelected ? .black.opacity(0.22) : .clear,
                            radius: isSelected ? 10 : 0,
                            y: isSelected ? 4 : 0
                        )
                )
                .offset(y: isHovered && !isSelected ? -1 : 0)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(MainWindowTheme.hoverAnimation, value: isHovered)
        .animation(MainWindowTheme.selectionAnimation, value: isSelected)
    }
}

private struct SidebarPrimaryButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.system(size: MainWindowTheme.scaled(14), weight: .medium))
                Text(title)
                    .font(.system(size: MainWindowTheme.scaled(13), weight: .semibold))
                Spacer()
            }
            .foregroundStyle(MainWindowTheme.textPrimary)
            .padding(.horizontal, MainWindowTheme.scaled(16))
            .padding(.vertical, MainWindowTheme.scaled(12))
            .background(
                RoundedRectangle(cornerRadius: MainWindowTheme.scaled(16), style: .continuous)
                    .fill(isHovered ? MainWindowTheme.hoverFill : Color.white.opacity(0.03))
                    .overlay(
                        RoundedRectangle(cornerRadius: MainWindowTheme.scaled(16), style: .continuous)
                            .strokeBorder(Color.white.opacity(0.16), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(isHovered ? 0.16 : 0.08), radius: isHovered ? 16 : 8, x: 0, y: isHovered ? 8 : 4)
            )
            .offset(y: isHovered ? -1 : 0)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(MainWindowTheme.hoverAnimation, value: isHovered)
    }
}

private struct SidebarSquareButton: View {
    let systemImage: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: MainWindowTheme.scaled(15), weight: .medium))
                .foregroundStyle(MainWindowTheme.textPrimary)
                .frame(width: MainWindowTheme.scaled(50), height: MainWindowTheme.scaled(50))
                .background(
                    RoundedRectangle(cornerRadius: MainWindowTheme.scaled(16), style: .continuous)
                        .fill(isHovered ? MainWindowTheme.hoverFill : Color.white.opacity(0.03))
                        .overlay(
                            RoundedRectangle(cornerRadius: MainWindowTheme.scaled(16), style: .continuous)
                                .strokeBorder(Color.white.opacity(0.16), lineWidth: 1)
                        )
                        .shadow(color: .black.opacity(isHovered ? 0.16 : 0.08), radius: isHovered ? 14 : 8, x: 0, y: isHovered ? 8 : 4)
                )
                .offset(y: isHovered ? -1 : 0)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(MainWindowTheme.hoverAnimation, value: isHovered)
    }
}

private struct SidebarLineRow: View {
    let icon: String
    let title: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: MainWindowTheme.scaled(13)))
                    .foregroundStyle(MainWindowTheme.textSecondary)
                    .frame(width: MainWindowTheme.scaled(16))

                Text(title)
                    .font(.system(size: MainWindowTheme.scaled(13), weight: .medium))
                    .foregroundStyle(MainWindowTheme.textSecondary)

                Spacer()
            }
            .padding(.horizontal, MainWindowTheme.scaled(12))
            .padding(.vertical, MainWindowTheme.scaled(10))
            .background(
                RoundedRectangle(cornerRadius: MainWindowTheme.scaled(10), style: .continuous)
                    .fill(isHovered ? MainWindowTheme.hoverFill : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(MainWindowTheme.hoverAnimation, value: isHovered)
    }
}

private struct SidebarProjectHeader: View {
    let name: String
    let isCollapsed: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: "chevron.down")
                    .font(.system(size: MainWindowTheme.scaled(10), weight: .medium))
                    .foregroundStyle(MainWindowTheme.textSecondary)
                    .rotationEffect(.degrees(isCollapsed ? -90 : 0))

                Image(systemName: "folder")
                    .font(.system(size: MainWindowTheme.scaled(14)))
                    .foregroundStyle(MainWindowTheme.textSecondary)

                Text(name)
                    .font(.system(size: MainWindowTheme.scaled(13), weight: .semibold))
                    .foregroundStyle(MainWindowTheme.textPrimary)

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, MainWindowTheme.scaled(10))
            .padding(.vertical, MainWindowTheme.scaled(6))
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: MainWindowTheme.scaled(12), style: .continuous)
                    .fill(isHovered ? Color.white.opacity(0.035) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(MainWindowTheme.hoverAnimation, value: isHovered)
        .animation(MainWindowTheme.selectionAnimation, value: isCollapsed)
    }
}

private struct ClaudeHookMenuCard: View {
    @State private var selectedMode = AppSettings.claudeHookDisplayMode

    let onSelect: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: MainWindowTheme.scaled(12)) {
            HStack(spacing: MainWindowTheme.scaled(8)) {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: MainWindowTheme.scaled(12), weight: .semibold))
                    .foregroundStyle(MainWindowTheme.textSecondary)

                Text("claude hook")
                    .font(.system(size: MainWindowTheme.scaled(12), weight: .semibold))
                    .foregroundStyle(MainWindowTheme.textPrimary)
            }

            Text("Choose where the hook appears.")
                .font(.system(size: MainWindowTheme.scaled(10)))
                .foregroundStyle(MainWindowTheme.textSecondary)

            VStack(spacing: MainWindowTheme.scaled(8)) {
                ForEach(ClaudeHookDisplayMode.allCases, id: \.self) { mode in
                    ClaudeHookModeButton(
                        mode: mode,
                        isSelected: selectedMode == mode
                    ) {
                        selectedMode = mode
                        AppSettings.setClaudeHookDisplayMode(mode)
                        onSelect()
                    }
                }
            }
        }
        .padding(MainWindowTheme.scaled(14))
        .mainWindowCard(
            fill: MainWindowTheme.sidebarPanel.opacity(0.98),
            border: Color.white.opacity(0.14),
            radius: MainWindowTheme.scaled(18),
            shadowOpacity: 0.24
        )
        .onReceive(NotificationCenter.default.publisher(for: .notchToggled)) { _ in
            selectedMode = AppSettings.claudeHookDisplayMode
        }
        .onReceive(NotificationCenter.default.publisher(for: .desktopMessageToggled)) { _ in
            selectedMode = AppSettings.claudeHookDisplayMode
        }
    }
}

private struct ClaudeHookModeButton: View {
    let mode: ClaudeHookDisplayMode
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: MainWindowTheme.scaled(10)) {
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: MainWindowTheme.scaled(13), weight: .medium))
                    .foregroundStyle(isSelected ? MainWindowTheme.accent : MainWindowTheme.textMuted)

                Text(ClaudeMessageDisplaySupport.menuTitle(for: mode))
                    .font(.system(size: MainWindowTheme.scaled(12), weight: .semibold))
                    .foregroundStyle(MainWindowTheme.textPrimary)

                Spacer()
            }
            .padding(.horizontal, MainWindowTheme.scaled(12))
            .padding(.vertical, MainWindowTheme.scaled(11))
            .background(
                RoundedRectangle(cornerRadius: MainWindowTheme.scaled(14), style: .continuous)
                    .fill(isSelected ? Color.white.opacity(0.10) : MainWindowTheme.panel)
                    .overlay(
                        RoundedRectangle(cornerRadius: MainWindowTheme.scaled(14), style: .continuous)
                            .strokeBorder(isSelected ? MainWindowTheme.borderStrong : MainWindowTheme.border, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

struct ThreadRowView: View {
    let title: String
    let gitBranch: String?
    let lastEventAt: Date
    let status: SidebarSessionStatus
    let isSelected: Bool
    let selectionNamespace: Namespace.ID
    let onSelect: () -> Void
    let onDelete: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onSelect) {
            HStack(alignment: .center, spacing: 10) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 6, height: 6)

                VStack(alignment: .leading, spacing: MainWindowTheme.scaled(2)) {
                    Text(title)
                        .font(.system(size: MainWindowTheme.scaled(13), weight: .medium))
                        .foregroundStyle(MainWindowTheme.textPrimary)
                        .lineLimit(1)

                    if let branch = gitBranch {
                        Text(branch)
                            .font(.system(size: MainWindowTheme.scaled(11)))
                            .foregroundStyle(MainWindowTheme.textMuted)
                            .lineLimit(1)
                    }
                }

                Spacer()

                SidebarSessionActivityView(status: status, timestamp: lastEventAt)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, MainWindowTheme.scaled(14))
            .padding(.vertical, MainWindowTheme.scaled(7))
            .contentShape(Rectangle())
            .background(
                ZStack {
                    if isSelected {
                        RoundedRectangle(cornerRadius: MainWindowTheme.scaled(14), style: .continuous)
                            .fill(Color.white.opacity(0.085))
                            .overlay(
                                RoundedRectangle(cornerRadius: MainWindowTheme.scaled(14), style: .continuous)
                                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                            )
                            .shadow(color: .black.opacity(0.18), radius: 16, x: 0, y: 10)
                            .matchedGeometryEffect(id: "thread-selection", in: selectionNamespace)
                    } else {
                        RoundedRectangle(cornerRadius: MainWindowTheme.scaled(14), style: .continuous)
                            .fill(isHovered ? MainWindowTheme.hoverFill : Color.clear)
                    }
                }
            )
            .offset(y: isHovered && !isSelected ? -1 : 0)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(MainWindowTheme.hoverAnimation, value: isHovered)
        .animation(MainWindowTheme.selectionAnimation, value: isSelected)
        .contextMenu {
            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private var statusColor: Color {
        status.color
    }
}

struct GlobalSessionRowView: View {
    let session: HookSessionInfo
    let status: SidebarSessionStatus
    let isSelected: Bool
    let selectionNamespace: Namespace.ID
    let onSelect: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 10) {
                Circle()
                    .fill(globalStatusColor)
                    .frame(width: 6, height: 6)

                VStack(alignment: .leading, spacing: MainWindowTheme.scaled(2)) {
                    Text(session.title ?? session.projectName)
                        .font(.system(size: MainWindowTheme.scaled(13), weight: .medium))
                        .foregroundStyle(MainWindowTheme.textPrimary)
                        .lineLimit(1)

                    HStack(spacing: MainWindowTheme.scaled(6)) {
                        Text(session.projectName)
                            .font(.system(size: MainWindowTheme.scaled(11)))
                            .foregroundStyle(MainWindowTheme.textMuted)
                            .lineLimit(1)

                        if let branch = session.gitBranch {
                            Text(branch)
                                .font(.system(size: MainWindowTheme.scaled(10), design: .monospaced))
                                .foregroundStyle(MainWindowTheme.textMuted)
                                .lineLimit(1)
                        }

                        if session.source == .history {
                            Text("Saved")
                                .font(.system(size: MainWindowTheme.scaled(9), weight: .semibold))
                                .foregroundStyle(MainWindowTheme.textMuted)
                                .padding(.horizontal, MainWindowTheme.scaled(6))
                                .padding(.vertical, MainWindowTheme.scaled(3))
                                .background(Color.white.opacity(0.05))
                                .clipShape(Capsule())
                        } else {
                            Text("Live")
                                .font(.system(size: MainWindowTheme.scaled(9), weight: .semibold))
                                .foregroundStyle(globalStatusColor)
                                .padding(.horizontal, MainWindowTheme.scaled(6))
                                .padding(.vertical, MainWindowTheme.scaled(3))
                                .background(globalStatusColor.opacity(0.12))
                                .clipShape(Capsule())
                        }
                    }
                }

                Spacer()

                SidebarSessionActivityView(status: status, timestamp: session.lastEventAt)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, MainWindowTheme.scaled(14))
            .padding(.vertical, MainWindowTheme.scaled(7))
            .background(
                ZStack {
                    if isSelected {
                        RoundedRectangle(cornerRadius: MainWindowTheme.scaled(14), style: .continuous)
                            .fill(Color.white.opacity(0.085))
                            .overlay(
                                RoundedRectangle(cornerRadius: MainWindowTheme.scaled(14), style: .continuous)
                                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                            )
                            .shadow(color: .black.opacity(0.18), radius: 16, x: 0, y: 10)
                            .matchedGeometryEffect(id: "thread-selection", in: selectionNamespace)
                    } else {
                        RoundedRectangle(cornerRadius: MainWindowTheme.scaled(14), style: .continuous)
                            .fill(isHovered ? MainWindowTheme.hoverFill : Color.clear)
                    }
                }
            )
            .contentShape(Rectangle())
            .offset(y: isHovered && !isSelected ? -1 : 0)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(MainWindowTheme.hoverAnimation, value: isHovered)
        .animation(MainWindowTheme.selectionAnimation, value: isSelected)
    }

    private var globalStatusColor: Color {
        status.color
    }
}

private struct SidebarSessionActivityView: View {
    let status: SidebarSessionStatus
    let timestamp: Date

    var body: some View {
        if status.showsActivityBadge, let label = status.activityLabel {
            Text(label)
                .font(.system(size: MainWindowTheme.scaled(10), weight: .semibold))
                .foregroundStyle(status.color)
                .padding(.horizontal, MainWindowTheme.scaled(8))
                .padding(.vertical, MainWindowTheme.scaled(5))
                .background(status.color.opacity(0.12))
                .clipShape(Capsule())
        } else {
            Text(timestamp.relativeFormatted)
                .font(.system(size: MainWindowTheme.scaled(11)))
                .foregroundStyle(MainWindowTheme.textMuted)
        }
    }
}

private extension SidebarSessionStatus {
    var color: Color {
        switch self {
        case .processing:
            return MainWindowTheme.accent
        case .waitingForInput, .active:
            return TerminalColors.green
        case .waitingForApproval:
            return TerminalColors.amber
        case .compacting:
            return TerminalColors.blue
        case .idle:
            return MainWindowTheme.textMuted
        case .ended:
            return TerminalColors.red.opacity(0.8)
        }
    }
}

extension Date {
    var relativeFormatted: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: self, relativeTo: Date())
    }
}
