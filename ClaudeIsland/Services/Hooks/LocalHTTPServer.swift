//
//  LocalHTTPServer.swift
//  ClaudeIsland
//
//  Local HTTP server for receiving Hook events from Claude CLI.
//  Reference: Masko Code's LocalServer.swift (NWListener based).
//
//  Endpoints:
//    GET  /health → 200 "ok" (hook script liveness check)
//    POST /hook   → receive Hook event JSON
//      - PermissionRequest: hold connection open for user decision
//      - Other events: 200 OK immediately
//

import Foundation
import Network
import os.log

private let logger = Logger(subsystem: "com.claudeisland", category: "HTTPServer")

// MARK: - Hook Event (from Bash script)

struct HookEvent: Codable {
    let hookEventName: String?
    let sessionId: String?
    let cwd: String?
    let content: String?
    let toolName: String?
    let toolInput: String?
    let terminalPid: Int?
    let shellPid: Int?

    // PermissionRequest fields
    let permissionRequest: PermissionRequestData?

    enum CodingKeys: String, CodingKey {
        case hookEventName = "hook_event_name"
        case sessionId = "session_id"
        case cwd
        case content
        case toolName = "tool_name"
        case toolInput = "tool_input"
        case terminalPid = "terminal_pid"
        case shellPid = "shell_pid"
        case permissionRequest = "permission_request"
    }
}

struct PermissionRequestData: Codable {
    let tool: String?
    let description: String?
    let input: String?
}

// MARK: - LocalHTTPServer

@Observable
final class LocalHTTPServer {
    private var listener: NWListener?
    private(set) var isRunning = false
    private(set) var port: UInt16

    private var stopped = false
    private var retryCount = 0
    private static let maxRetries = 3
    private static let maxPortAttempts: UInt16 = 10

    /// Callback for hook events (non-permission)
    var onEventReceived: ((HookEvent) -> Void)?

    /// Callback for permission requests (connection held open)
    var onPermissionRequest: ((HookEvent, NWConnection) -> Void)?

    init() {
        self.port = AppSettings.serverPort
    }

    // MARK: - Lifecycle

    func start() throws {
        stopped = false
        listener?.cancel()
        listener = nil

        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true

        guard let nwPort = NWEndpoint.Port(rawValue: port) else { return }
        listener = try NWListener(using: params, on: nwPort)

        listener?.newConnectionHandler = { [weak self] connection in
            self?.handleConnection(connection)
        }

        listener?.stateUpdateHandler = { [weak self] state in
            DispatchQueue.main.async {
                guard let self else { return }
                switch state {
                case .ready:
                    self.isRunning = true
                    self.retryCount = 0
                    if self.port != AppSettings.serverPort {
                        AppSettings.serverPort = self.port
                    }
                    logger.info("HTTP Server listening on port \(self.port)")

                case .failed(let error):
                    self.isRunning = false
                    self.listener?.cancel()
                    self.listener = nil
                    self.tryNextPort(reason: "failed", error: error)

                case .waiting(let error):
                    self.isRunning = false
                    self.listener?.cancel()
                    self.listener = nil
                    self.tryNextPort(reason: "waiting", error: error)

                case .cancelled:
                    self.isRunning = false

                default:
                    break
                }
            }
        }

        listener?.start(queue: .global(qos: .userInitiated))
    }

    func stop() {
        stopped = true
        listener?.cancel()
        listener = nil
        isRunning = false
        logger.info("HTTP Server stopped")
    }

    /// Respond to a held-open PermissionRequest connection
    func respondToPermission(connection: NWConnection, approved: Bool) {
        if approved {
            sendResponse(connection: connection, status: "200 OK", body: "OK")
        } else {
            sendResponse(connection: connection, status: "403 Forbidden", body: "Denied")
        }
    }

    // MARK: - Port Management

    private func tryNextPort(reason: String, error: NWError) {
        guard !stopped else { return }
        let nextPort = port + 1
        if nextPort < AppSettings.defaultServerPort + Self.maxPortAttempts {
            logger.info("Port \(self.port) \(reason): \(error) - trying \(nextPort)...")
            port = nextPort
            try? start()
        } else {
            guard retryCount < Self.maxRetries else {
                logger.error("Server gave up after trying ports \(AppSettings.defaultServerPort)-\(self.port)")
                return
            }
            retryCount += 1
            port = AppSettings.defaultServerPort
            let delay = min(Double(2 << retryCount), 30.0)
            logger.info("All ports busy - retry \(self.retryCount)/\(Self.maxRetries) in \(Int(delay))s")
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self, !self.stopped else { return }
                try? self.start()
            }
        }
    }

    // MARK: - Connection Handling

    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: .global(qos: .userInitiated))

        var receivedData = Data()

        func readMore() {
            connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
                if let data {
                    receivedData.append(data)
                }

                if self?.hasCompleteHTTPRequest(receivedData) == true || isComplete || error != nil {
                    self?.processRequest(receivedData, connection: connection)
                } else {
                    readMore()
                }
            }
        }

        readMore()
    }

    private func hasCompleteHTTPRequest(_ data: Data) -> Bool {
        guard let str = String(data: data, encoding: .utf8) else { return false }

        if str.hasPrefix("GET ") {
            return str.contains("\r\n\r\n")
        }

        guard let separatorRange = str.range(of: "\r\n\r\n") else { return false }
        let headers = str[str.startIndex..<separatorRange.lowerBound]
        let body = str[separatorRange.upperBound...]

        if let clRange = headers.range(of: "Content-Length: ", options: .caseInsensitive) {
            let afterCL = headers[clRange.upperBound...]
            if let lineEnd = afterCL.firstIndex(of: "\r"),
               let contentLength = Int(afterCL[afterCL.startIndex..<lineEnd]) {
                return body.utf8.count >= contentLength
            }
        }

        return true
    }

    private func processRequest(_ data: Data, connection: NWConnection) {
        guard let httpString = String(data: data, encoding: .utf8) else {
            sendResponse(connection: connection, status: "400 Bad Request", body: "Bad Request")
            return
        }

        let firstLine = httpString.components(separatedBy: "\r\n").first ?? ""

        // GET /health
        if firstLine.contains("GET /health") {
            sendResponse(connection: connection, status: "200 OK", body: "ok")
            return
        }

        // Extract body for POST routes
        guard let bodyRange = httpString.range(of: "\r\n\r\n") else {
            sendResponse(connection: connection, status: "400 Bad Request", body: "No body")
            return
        }
        let bodyString = String(httpString[bodyRange.upperBound...])
        guard let bodyData = bodyString.data(using: .utf8) else {
            sendResponse(connection: connection, status: "400 Bad Request", body: "Invalid body")
            return
        }

        // POST /hook
        if firstLine.contains("POST /hook") {
            let decoder = JSONDecoder()
            if let event = try? decoder.decode(HookEvent.self, from: bodyData) {
                logger.info("Hook received: \(event.hookEventName ?? "unknown")")

                // PermissionRequest: hold connection open
                if event.hookEventName == "PermissionRequest",
                   let handler = onPermissionRequest {
                    DispatchQueue.main.async {
                        handler(event, connection)
                    }
                    // Forward to event handler for tracking too
                    DispatchQueue.main.async { [weak self] in
                        self?.onEventReceived?(event)
                    }
                    return
                }

                // Other events: fire and forward
                DispatchQueue.main.async { [weak self] in
                    self?.onEventReceived?(event)
                }
            } else {
                logger.warning("Hook received but failed to decode JSON")
            }
            sendResponse(connection: connection, status: "200 OK", body: "OK")
            return
        }

        sendResponse(connection: connection, status: "404 Not Found", body: "Not Found")
    }

    // MARK: - HTTP Response

    private func sendResponse(connection: NWConnection, status: String, body: String) {
        let response = "HTTP/1.1 \(status)\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"
        connection.send(content: response.data(using: .utf8), completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    deinit {
        listener?.cancel()
    }
}
