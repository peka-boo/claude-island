//
//  ChatViewModel.swift
//  ClaudeIsland
//
//  ViewModel for the chat content area.
//  Manages message display, sending, streaming, and CLI session lifecycle.
//

import Foundation
import SwiftData
import os.log

private let logger = Logger(subsystem: "com.claudeisland", category: "Chat")

// MARK: - ChatViewModel

@Observable
@MainActor
final class ChatViewModel {

    // MARK: - State

    var messages: [MessageDTO] = []
    var inputText: String = ""
    var isProcessing = false
    var isStreaming = false
    var currentStreamingText: String = ""
    var currentThinkingText: String = ""
    var currentThreadId: String?
    var threadInfo: ThreadDTO?
    var error: String?

    // MARK: - Dependencies

    private var dataActor: BackgroundDataActor?
    private let cliManager: CLISessionManager

    init(cliManager: CLISessionManager) {
        self.cliManager = cliManager
    }

    func configure(with container: ModelContainer) {
        self.dataActor = BackgroundDataActor(modelContainer: container)
    }

    // MARK: - Load Messages

    func loadThread(_ threadId: String) async {
        currentThreadId = threadId
        guard let actor = dataActor else { return }

        do {
            messages = try await actor.fetchMessages(threadId: threadId)

            // Load thread info
            let allThreads = try await actor.fetchAllThreads()
            threadInfo = allThreads.first { $0.id == threadId }

            // Check if CLI session is active
            isProcessing = await cliManager.isActive(threadId: threadId)
        } catch {
            logger.error("Failed to load thread: \(error)")
        }
    }

    // MARK: - Send Message

    func sendMessage() async {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let threadId = currentThreadId else { return }

        inputText = ""
        isProcessing = true
        isStreaming = true
        currentStreamingText = ""
        currentThinkingText = ""
        error = nil

        guard let actor = dataActor else { return }

        do {
            // Save user message
            _ = try await actor.appendMessage(
                threadId: threadId,
                role: .user,
                content: text
            )

            // Reload to show user message
            messages = try await actor.fetchMessages(threadId: threadId)

            // Get thread info for working directory
            let allThreads = try await actor.fetchAllThreads()
            guard let thread = allThreads.first(where: { $0.id == threadId }) else { return }

            // Get project path
            if let projectId = thread.projectId {
                let projects = try await actor.fetchAllProjects()
                if let project = projects.first(where: { $0.id == projectId }) {
                    // Set up stream event handler
                    await setupStreamHandler(threadId: threadId)

                    // Check if this is a new session or continuation
                    let isActive = await cliManager.isActive(threadId: threadId)

                    if isActive {
                        // Send follow-up message to existing process
                        await cliManager.sendMessage(threadId: threadId, message: text)
                    } else if let cliSessionId = thread.cliSessionId {
                        // Resume existing CLI session
                        await cliManager.resumeSession(
                            threadId: threadId,
                            cliSessionId: cliSessionId,
                            cwd: project.path
                        )
                        // Send the message after a brief delay for process startup
                        try? await Task.sleep(for: .milliseconds(500))
                        await cliManager.sendMessage(threadId: threadId, message: text)
                    } else {
                        // Start new session
                        await cliManager.startSession(
                            threadId: threadId,
                            cwd: project.path,
                            prompt: text
                        )
                    }
                }
            }
        } catch {
            logger.error("Failed to send message: \(error)")
            self.error = "Failed to send message: \(error.localizedDescription)"
            isProcessing = false
            isStreaming = false
        }
    }

    // MARK: - Interrupt

    func interrupt() async {
        guard let threadId = currentThreadId else { return }
        await cliManager.interruptSession(threadId: threadId)
    }

    // MARK: - Stream Handling

    private func setupStreamHandler(threadId: String) async {
        await cliManager.setOnStreamEvent { [weak self] eventThreadId, event in
            guard eventThreadId == threadId else { return }
            Task { @MainActor in
                self?.handleStreamEvent(event)
            }
        }

        await cliManager.setOnProcessEnded { [weak self] endedThreadId in
            guard endedThreadId == threadId else { return }
            Task { @MainActor in
                self?.handleProcessEnded()
            }
        }
    }

    private func handleStreamEvent(_ event: CLIStreamEvent) {
        switch event {
        case .thinking(let text):
            currentThinkingText = text

        case .text(let text):
            currentStreamingText += text

        case .toolUse(let id, let name, let input):
            // Save tool use as a message
            Task {
                guard let actor = dataActor, let threadId = currentThreadId else { return }
                _ = try? await actor.appendMessage(
                    threadId: threadId,
                    role: .assistant,
                    content: "Using tool: \(name)",
                    toolName: name,
                    toolInput: input
                )
                messages = try await actor.fetchMessages(threadId: threadId)
            }

        case .toolResult(_, _, let output):
            // Tool results are handled as part of the ongoing stream
            break

        case .result(let info):
            // Save the final assistant message
            Task {
                guard let actor = dataActor, let threadId = currentThreadId else { return }

                if !currentStreamingText.isEmpty {
                    _ = try? await actor.appendMessage(
                        threadId: threadId,
                        role: .assistant,
                        content: currentStreamingText,
                        thinking: currentThinkingText.isEmpty ? nil : currentThinkingText,
                        costUsd: info.costUsd,
                        tokensIn: info.tokensIn,
                        tokensOut: info.tokensOut
                    )
                }

                // Update thread with CLI session ID
                if !info.sessionId.isEmpty {
                    let allThreads = try await actor.fetchAllThreads()
                    if let thread = allThreads.first(where: { $0.id == threadId }),
                       thread.cliSessionId == nil {
                        // Update CLI session ID for future resume
                        try? await actor.updateThreadStatus(threadId: threadId, status: .idle)
                    }
                }

                messages = try await actor.fetchMessages(threadId: threadId)
                currentStreamingText = ""
                currentThinkingText = ""
                isProcessing = false
                isStreaming = false
            }

        case .sessionStart(let sessionId):
            logger.info("Session started: \(sessionId)")

        case .error(let message):
            error = message
            isProcessing = false
            isStreaming = false

        case .unknown:
            break
        }
    }

    private func handleProcessEnded() {
        isProcessing = false
        isStreaming = false
        currentStreamingText = ""
        currentThinkingText = ""

        // Reload messages to get final state
        Task {
            guard let actor = dataActor, let threadId = currentThreadId else { return }
            messages = try await actor.fetchMessages(threadId: threadId)
            try? await actor.updateThreadStatus(threadId: threadId, status: .idle)
        }
    }
}
