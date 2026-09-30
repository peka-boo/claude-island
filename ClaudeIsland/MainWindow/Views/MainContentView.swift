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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var sidebarVM = SidebarViewModel()
    @State private var chatVM: ChatViewModel

    let cliManager: CLIManaging

    init(cliManager: CLIManaging) {
        self.cliManager = cliManager
        self._chatVM = State(initialValue: ChatViewModel(cliManager: cliManager))
    }

    var body: some View {
        ZStack {
            MainWindowBackdrop()

            HStack(spacing: 0) {
                SidebarView(viewModel: sidebarVM)
                    .frame(width: MainWindowTheme.scaled(486))
                    .frame(maxHeight: .infinity)

                Rectangle()
                    .fill(MainWindowTheme.separator)
                    .frame(width: 1)

                ZStack {
                    if let threadId = sidebarVM.selectedThreadId {
                        ChatContentView(viewModel: chatVM, threadId: threadId)
                            .id(MainWindowDetailIdentitySupport.identity(for: threadId))
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .transition(
                                MainWindowTheme.adaptiveTransition(
                                    MainWindowTheme.detailSwapTransition,
                                    reduceMotion: reduceMotion
                                )
                            )
                    } else {
                        WelcomeView(onNewChat: { path in
                            Task {
                                _ = await sidebarVM.createNewThread(projectPath: path)
                            }
                        })
                        .id(MainWindowDetailIdentitySupport.identity(for: nil))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .transition(
                            MainWindowTheme.adaptiveTransition(
                                MainWindowTheme.detailSwapTransition,
                                reduceMotion: reduceMotion
                            )
                        )
                    }
                }
                .animation(
                    MainWindowTheme.adaptiveAnimation(
                        MainWindowTheme.contentSwapAnimation,
                        reduceMotion: reduceMotion
                    ),
                    value: sidebarVM.selectedThreadId
                )
            }
            .background(MainWindowTheme.workspace)
            .clipShape(RoundedRectangle(cornerRadius: 0, style: .continuous))
        }
        .frame(minWidth: 1100, idealWidth: 1100, minHeight: 720, idealHeight: 720)
        .preferredColorScheme(.dark)
        .onAppear {
            sidebarVM.configure(with: DataStore.shared)
            chatVM.configure(with: DataStore.shared)
            Task { await sidebarVM.loadData() }
        }
        .onChange(of: chatVM.threadInfo?.updatedAt) { _, _ in
            sidebarVM.refreshThreadSnapshot(chatVM.threadInfo)
        }
        .sheet(isPresented: $sidebarVM.showImportSheet) {
            ImportSessionView(onImportComplete: {
                Task { await sidebarVM.loadData() }
            })
        }
    }
}
