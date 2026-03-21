//
//  CLISessionManager.swift
//  ClaudeIsland
//
//  Manages Claude CLI subprocess lifecycle.
//  Each conversation thread maps to one CLI process using:
//    claude -p --output-format stream-json --verbose --input-format stream-json
//

import Foundation
import os.log

private let logger = Logger(subsystem: "com.claudeisland", category: "CLI")

// MARK: - CLISessionManager

/// Manages active Claude CLI subprocesses.
/// Uses Swift actor for thread safety.
actor CLISessionManager {

    /// Active CLI process info indexed by thread ID
    private var activeProcesses: [String: CLIProcess] = [:]

    /// The stream parser
    private let parser = CLIStreamParser()

    /// Callback for stream events
    private(set) var onStreamEvent: ((String, CLIStreamEvent) -> Void)?

    /// Callback for process termination
    private(set) var onProcessEnded: ((String) -> Void)?

    /// Setters for callbacks
    func setOnStreamEvent(_ closure: @escaping (String, CLIStreamEvent) -> Void) {
        self.onStreamEvent = closure
    }
    
    func setOnProcessEnded(_ closure: @escaping (String) -> Void) {
        self.onProcessEnded = closure
    }

    /// Path to the claude CLI binary
    private let claudePath: String

    init() {
        // Find claude binary
        if FileManager.default.fileExists(atPath: "/Users/mac/.local/bin/claude") {
            claudePath = "/Users/mac/.local/bin/claude"
        } else {
            // Fallback: search PATH
            let pipe = Pipe()
            let which = Process()
            which.executableURL = URL(fileURLWithPath: "/usr/bin/which")
            which.arguments = ["claude"]
            which.standardOutput = pipe
            try? which.run()
            which.waitUntilExit()
            let pathData = pipe.fileHandleForReading.readDataToEndOfFile()
            claudePath = String(data: pathData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? "/usr/local/bin/claude"
        }
        logger.info("Claude CLI path: \(self.claudePath)")
    }

    // MARK: - Session Lifecycle

    /// Start a new conversation in the given working directory.
    /// Returns the CLI session_id once the first event arrives.
    func startSession(threadId: String, cwd: String, prompt: String) {
        guard activeProcesses[threadId] == nil else {
            logger.warning("Thread \(threadId) already has an active process")
            return
        }

        var args = [
            "-p",
            "--output-format", "stream-json",
            "--verbose",
        ]

        let process = Process()
        process.executableURL = URL(fileURLWithPath: claudePath)
        process.currentDirectoryURL = URL(fileURLWithPath: cwd)
        process.environment = Foundation.ProcessInfo.processInfo.environment

        // Set up stdin for the prompt
        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()

        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        process.arguments = args

        let cliProcess = CLIProcess(
            threadId: threadId,
            process: process,
            stdinPipe: stdinPipe,
            stdoutPipe: stdoutPipe
        )
        activeProcesses[threadId] = cliProcess

        // Write prompt to stdin and close (single-turn mode)
        let promptData = prompt.data(using: .utf8) ?? Data()
        stdinPipe.fileHandleForWriting.write(promptData)
        stdinPipe.fileHandleForWriting.closeFile()

        // Read stdout on background queue
        let threadIdCopy = threadId
        stdoutPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                // EOF — process is ending
                handle.readabilityHandler = nil
                return
            }

            if let output = String(data: data, encoding: .utf8) {
                let lines = output.components(separatedBy: .newlines)
                for line in lines {
                    guard let self else { return }
                    let parser = CLIStreamParser()
                    if let event = parser.parseLine(line) {
                        Task {
                            await self.triggerStreamEvent(threadId: threadIdCopy, event: event)
                        }
                    }
                }
            }
        }

        // Handle process termination
        process.terminationHandler = { [weak self] proc in
            logger.info("CLI process for thread \(threadIdCopy) terminated with code \(proc.terminationStatus)")
            Task {
                await self?.handleProcessTermination(threadId: threadIdCopy)
            }
        }

        // Launch
        do {
            try process.run()
            logger.info("Started CLI process for thread \(threadId), PID: \(process.processIdentifier)")
        } catch {
            logger.error("Failed to start CLI process: \(error)")
            activeProcesses.removeValue(forKey: threadId)
        }
    }

    /// Resume an existing Claude CLI session (for takeover from global monitor).
    func resumeSession(threadId: String, cliSessionId: String, cwd: String) {
        guard activeProcesses[threadId] == nil else {
            logger.warning("Thread \(threadId) already has an active process")
            return
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: claudePath)
        process.currentDirectoryURL = URL(fileURLWithPath: cwd)
        process.environment = Foundation.ProcessInfo.processInfo.environment

        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()

        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        process.arguments = [
            "-p",
            "--output-format", "stream-json",
            "--verbose",
            "--resume", cliSessionId,
            "--input-format", "stream-json",
        ]

        let cliProcess = CLIProcess(
            threadId: threadId,
            process: process,
            stdinPipe: stdinPipe,
            stdoutPipe: stdoutPipe
        )
        activeProcesses[threadId] = cliProcess

        // Read stdout
        let threadIdCopy = threadId
        stdoutPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                handle.readabilityHandler = nil
                return
            }
            if let output = String(data: data, encoding: .utf8) {
                let lines = output.components(separatedBy: .newlines)
                for line in lines {
                    guard let self else { return }
                    let parser = CLIStreamParser()
                    if let event = parser.parseLine(line) {
                        Task {
                            await self.triggerStreamEvent(threadId: threadIdCopy, event: event)
                        }
                    }
                }
            }
        }

        process.terminationHandler = { [weak self] proc in
            logger.info("Resumed CLI process for thread \(threadIdCopy) terminated with code \(proc.terminationStatus)")
            Task {
                await self?.handleProcessTermination(threadId: threadIdCopy)
            }
        }

        do {
            try process.run()
            logger.info("Resumed CLI session \(cliSessionId) for thread \(threadId), PID: \(process.processIdentifier)")
        } catch {
            logger.error("Failed to resume CLI process: \(error)")
            activeProcesses.removeValue(forKey: threadId)
        }
    }

    /// Send a follow-up message to an active session (stream-json input mode).
    func sendMessage(threadId: String, message: String) {
        guard let cliProcess = activeProcesses[threadId] else {
            logger.warning("No active process for thread \(threadId)")
            return
        }

        // stream-json input format: {"type": "user", "content": "..."}
        let inputPayload: [String: Any] = [
            "type": "user",
            "content": message,
        ]

        guard let data = try? JSONSerialization.data(withJSONObject: inputPayload),
              var jsonString = String(data: data, encoding: .utf8) else {
            return
        }
        jsonString.append("\n")

        if let writeData = jsonString.data(using: .utf8) {
            cliProcess.stdinPipe.fileHandleForWriting.write(writeData)
        }
    }

    /// Send SIGINT to gracefully interrupt Claude's processing.
    func interruptSession(threadId: String) {
        guard let cliProcess = activeProcesses[threadId],
              cliProcess.process.isRunning else { return }

        kill(cliProcess.process.processIdentifier, SIGINT)
        logger.info("Sent SIGINT to thread \(threadId)")
    }

    /// Terminate a session's CLI process.
    func stopSession(threadId: String) {
        guard let cliProcess = activeProcesses[threadId] else { return }

        if cliProcess.process.isRunning {
            cliProcess.process.terminate() // SIGTERM

            // Force kill after 2 seconds if still running
            DispatchQueue.global().asyncAfter(deadline: .now() + 2) {
                if cliProcess.process.isRunning {
                    kill(cliProcess.process.processIdentifier, SIGKILL)
                    logger.warning("Force killed process for thread \(threadId)")
                }
            }
        }

        activeProcesses.removeValue(forKey: threadId)
    }

    /// Whether a thread has an active CLI process
    func isActive(threadId: String) -> Bool {
        activeProcesses[threadId]?.process.isRunning ?? false
    }

    /// Terminate all active processes (called on app exit)
    func terminateAll() {
        for (threadId, cliProcess) in activeProcesses {
            if cliProcess.process.isRunning {
                cliProcess.process.terminate()
                logger.info("Terminated process for thread \(threadId) on app exit")
            }
        }
        activeProcesses.removeAll()
    }

    // MARK: - Private

    private func handleProcessTermination(threadId: String) {
        activeProcesses.removeValue(forKey: threadId)
        triggerProcessEnded(threadId: threadId)
    }

    private func triggerStreamEvent(threadId: String, event: CLIStreamEvent) {
        let callback = self.onStreamEvent
        Task { @MainActor in
            callback?(threadId, event)
        }
    }

    private func triggerProcessEnded(threadId: String) {
        let callback = self.onProcessEnded
        Task { @MainActor in
            callback?(threadId)
        }
    }
}

// MARK: - CLIProcess

/// Holds references to a running CLI subprocess and its I/O pipes.
private struct CLIProcess {
    let threadId: String
    let process: Process
    let stdinPipe: Pipe
    let stdoutPipe: Pipe
}
