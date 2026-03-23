//
//  CLISessionManager.swift
//  ClaudeIsland
//
//  Manages Claude CLI subprocess lifecycle for the main window.
//  Each send launches a print-mode stream-json turn, optionally resumed from
//  a persisted Claude session ID.
//

import Foundation
import os.log

enum CLIPermissionMode: String, Sendable {
    case `default` = "default"
    case bypassPermissions = "bypassPermissions"
}

actor CLISessionManager {
    nonisolated private static let logger = Logger(subsystem: "com.claudeisland", category: "CLI")
    static let shared = CLISessionManager()

    private var activeProcesses: [String: CLIProcess] = [:]
    private var stdoutBuffers: [String: String] = [:]
    private var stderrBuffers: [String: String] = [:]

    private(set) var onStreamEvent: ((String, CLIStreamEvent) -> Void)?
    private(set) var onProcessEnded: ((String) -> Void)?

    func setOnStreamEvent(_ closure: @escaping (String, CLIStreamEvent) -> Void) {
        self.onStreamEvent = closure
    }

    func setOnProcessEnded(_ closure: @escaping (String) -> Void) {
        self.onProcessEnded = closure
    }

    private let claudePath: String

    init() {
        if FileManager.default.fileExists(atPath: "/Users/mac/.local/bin/claude") {
            claudePath = "/Users/mac/.local/bin/claude"
        } else {
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
        Self.logger.info("Claude CLI path: \(self.claudePath)")
    }

    // MARK: - Session Lifecycle

    func runTurn(
        threadId: String,
        cwd: String,
        prompt: String,
        cliSessionId: String? = nil,
        sessionName: String? = nil,
        permissionMode: CLIPermissionMode? = nil
    ) {
        _ = launchTurn(
            threadId: threadId,
            cwd: cwd,
            prompt: prompt,
            cliSessionId: cliSessionId,
            sessionName: sessionName,
            permissionMode: permissionMode
        )
    }

    func sendDetachedTurn(
        sessionId: String,
        cwd: String,
        prompt: String,
        permissionMode: CLIPermissionMode? = .default
    ) -> Bool {
        guard let detachedThreadId = SessionMessageTransportSupport.detachedThreadId(for: sessionId) else {
            Self.logger.warning("Detached turn requested without a valid session id")
            return false
        }

        let settingsFileURL: URL
        do {
            settingsFileURL = try DetachedResumeSettingsSupport.writeSanitizedSettingsFile(cwd: cwd)
        } catch {
            Self.logger.error("Failed to build detached resume settings: \(error.localizedDescription, privacy: .public)")
            return false
        }

        return launchTurn(
            threadId: detachedThreadId,
            cwd: cwd,
            prompt: prompt,
            cliSessionId: sessionId,
            sessionName: nil,
            permissionMode: permissionMode,
            settingSources: "",
            settingsFileURL: settingsFileURL
        )
    }

    func interruptSession(threadId: String) {
        guard let cliProcess = activeProcesses[threadId],
              cliProcess.process.isRunning else { return }

        kill(cliProcess.process.processIdentifier, SIGINT)
        Self.logger.info("Sent SIGINT to thread \(threadId)")
    }

    func stopSession(threadId: String) {
        guard let cliProcess = activeProcesses[threadId] else { return }

        if cliProcess.process.isRunning {
            cliProcess.process.terminate()

            DispatchQueue.global().asyncAfter(deadline: .now() + 2) {
                if cliProcess.process.isRunning {
                    kill(cliProcess.process.processIdentifier, SIGKILL)
                    Self.logger.warning("Force killed process for thread \(threadId)")
                }
            }
        }

        activeProcesses.removeValue(forKey: threadId)
        stdoutBuffers.removeValue(forKey: threadId)
        stderrBuffers.removeValue(forKey: threadId)
        DetachedResumeSettingsSupport.removeSanitizedSettingsFile(at: cliProcess.settingsFileURL)
    }

    func isActive(threadId: String) -> Bool {
        activeProcesses[threadId]?.process.isRunning ?? false
    }

    func terminateAll() {
        for (threadId, cliProcess) in activeProcesses {
            if cliProcess.process.isRunning {
                cliProcess.process.terminate()
                Self.logger.info("Terminated process for thread \(threadId) on app exit")
            }
            DetachedResumeSettingsSupport.removeSanitizedSettingsFile(at: cliProcess.settingsFileURL)
        }
        activeProcesses.removeAll()
        stdoutBuffers.removeAll()
        stderrBuffers.removeAll()
    }

    // MARK: - Launching

    @discardableResult
    private func launchTurn(
        threadId: String,
        cwd: String,
        prompt: String,
        cliSessionId: String?,
        sessionName: String?,
        permissionMode: CLIPermissionMode?,
        settingSources: String? = nil,
        settingsFileURL: URL? = nil
    ) -> Bool {
        guard activeProcesses[threadId] == nil else {
            Self.logger.warning("Thread \(threadId) already has an active process")
            DetachedResumeSettingsSupport.removeSanitizedSettingsFile(at: settingsFileURL)
            return false
        }

        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPrompt.isEmpty else {
            Self.logger.warning("Ignoring empty prompt for thread \(threadId)")
            DetachedResumeSettingsSupport.removeSanitizedSettingsFile(at: settingsFileURL)
            return false
        }

        var args = [
            "-p",
            "--output-format", "stream-json",
            "--verbose",
            "--include-partial-messages",
        ]

        if let settingSources {
            args.append(contentsOf: ["--setting-sources", settingSources])
        }

        if let settingsFileURL {
            args.append(contentsOf: ["--settings", settingsFileURL.path])
        }

        if let permissionMode {
            if permissionMode == .bypassPermissions {
                args.append("--allow-dangerously-skip-permissions")
            }
            args.append(contentsOf: ["--permission-mode", permissionMode.rawValue])
        }

        if let resumeId = normalizeCLISessionId(cliSessionId) {
            args.append(contentsOf: ["--resume", resumeId])
        } else if let sessionName, !sessionName.isEmpty {
            args.append(contentsOf: ["--name", sessionName])
        }

        args.append(trimmedPrompt)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: claudePath)
        process.currentDirectoryURL = URL(fileURLWithPath: cwd)
        process.environment = Foundation.ProcessInfo.processInfo.environment

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        process.arguments = args

        let cliProcess = CLIProcess(
            threadId: threadId,
            process: process,
            stdoutPipe: stdoutPipe,
            stderrPipe: stderrPipe,
            settingsFileURL: settingsFileURL
        )
        activeProcesses[threadId] = cliProcess
        stdoutBuffers[threadId] = ""
        stderrBuffers[threadId] = ""

        let threadIdCopy = threadId
        stdoutPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                handle.readabilityHandler = nil
                Task {
                    await self?.flushStdoutBuffer(for: threadIdCopy)
                }
                return
            }

            Task {
                await self?.consumeStdoutChunk(data, for: threadIdCopy)
            }
        }

        stderrPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                handle.readabilityHandler = nil
                Task {
                    await self?.flushStderrBuffer(for: threadIdCopy)
                }
                return
            }

            Task {
                await self?.consumeStderrChunk(data, for: threadIdCopy)
            }
        }

        process.terminationHandler = { [weak self] proc in
            Self.logger.info("CLI process for thread \(threadIdCopy) terminated with code \(proc.terminationStatus)")
            Task {
                await self?.handleProcessTermination(threadId: threadIdCopy, exitCode: proc.terminationStatus)
            }
        }

        do {
            try process.run()
            Self.logger.info("Started CLI turn for thread \(threadId), PID: \(process.processIdentifier)")
            return true
        } catch {
            Self.logger.error("Failed to start CLI process: \(error.localizedDescription, privacy: .public)")
            activeProcesses.removeValue(forKey: threadId)
            stdoutBuffers.removeValue(forKey: threadId)
            stderrBuffers.removeValue(forKey: threadId)
            DetachedResumeSettingsSupport.removeSanitizedSettingsFile(at: settingsFileURL)
            triggerStreamEvent(threadId: threadId, event: .error("Failed to start Claude CLI: \(error.localizedDescription)"))
            return false
        }
    }

    // MARK: - Output Handling

    private func handleProcessTermination(threadId: String, exitCode: Int32) {
        flushStdoutBuffer(for: threadId)
        flushStderrBuffer(for: threadId)

        if exitCode != 0,
           let stderr = stderrBuffers[threadId]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !stderr.isEmpty {
            triggerStreamEvent(threadId: threadId, event: .error(stderr))
        }

        let cliProcess = activeProcesses.removeValue(forKey: threadId)
        stdoutBuffers.removeValue(forKey: threadId)
        stderrBuffers.removeValue(forKey: threadId)
        DetachedResumeSettingsSupport.removeSanitizedSettingsFile(at: cliProcess?.settingsFileURL)
        triggerProcessEnded(threadId: threadId)
    }

    private func consumeStdoutChunk(_ data: Data, for threadId: String) {
        guard let chunk = String(data: data, encoding: .utf8), !chunk.isEmpty else { return }

        var buffer = stdoutBuffers[threadId, default: ""]
        buffer.append(chunk)

        let lines = buffer.components(separatedBy: .newlines)
        stdoutBuffers[threadId] = lines.last ?? ""

        let parser = CLIStreamParser()
        for line in lines.dropLast() {
            for event in parser.parseLine(line) {
                triggerStreamEvent(threadId: threadId, event: event)
            }
        }
    }

    private func flushStdoutBuffer(for threadId: String) {
        guard let remainder = stdoutBuffers[threadId] else { return }

        let trimmed = remainder.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            stdoutBuffers[threadId] = ""
            return
        }

        let parser = CLIStreamParser()
        for event in parser.parseLine(trimmed) {
            triggerStreamEvent(threadId: threadId, event: event)
        }
        stdoutBuffers[threadId] = ""
    }

    private func consumeStderrChunk(_ data: Data, for threadId: String) {
        guard let chunk = String(data: data, encoding: .utf8), !chunk.isEmpty else { return }
        stderrBuffers[threadId, default: ""].append(chunk)
    }

    private func flushStderrBuffer(for threadId: String) {
        if stderrBuffers[threadId] == nil {
            stderrBuffers[threadId] = ""
        }
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

private struct CLIProcess {
    let threadId: String
    let process: Process
    let stdoutPipe: Pipe
    let stderrPipe: Pipe
    let settingsFileURL: URL?
}
