//
//  MainContentView.swift
//  ClaudeIsland
//
//  Root view for the main window using NavigationSplitView.
//  Provides sidebar + detail layout per Apple HIG.
//

import SwiftUI
import SwiftData

struct MainContentView: View {
    @State private var sidebarVM = SidebarViewModel()
    @State private var chatVM: ChatViewModel
    @State private var columnVisibility = NavigationSplitViewVisibility.all

    let cliManager: CLISessionManager

    init(cliManager: CLISessionManager) {
        self.cliManager = cliManager
        self._chatVM = State(initialValue: ChatViewModel(cliManager: cliManager))
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(viewModel: sidebarVM)
                .navigationSplitViewColumnWidth(min: 220, ideal: 280, max: 360)
        } detail: {
            if let threadId = sidebarVM.selectedThreadId {
                ChatContentView(viewModel: chatVM, threadId: threadId)
            } else {
                WelcomeView(onNewChat: { path in
                    Task {
                        _ = await sidebarVM.createNewThread(projectPath: path)
                    }
                })
            }
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 900, minHeight: 600)
        .preferredColorScheme(.dark)
        .onAppear {
            sidebarVM.configure(with: DataStore.shared)
            chatVM.configure(with: DataStore.shared)
            Task { await sidebarVM.loadData() }
        }
        .onChange(of: sidebarVM.selectedThreadId) { _, newId in
            if let threadId = newId {
                Task { await chatVM.loadThread(threadId) }
            }
        }
        .sheet(isPresented: $sidebarVM.showImportSheet) {
            ImportSessionView(onImportComplete: {
                Task { await sidebarVM.loadData() }
            })
        }
    }
}
