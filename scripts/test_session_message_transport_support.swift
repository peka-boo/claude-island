import Foundation

@inline(__always)
func assertMessageTransport(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        fputs("Assertion failed: \(message)\n", stderr)
        exit(1)
    }
}

@main
struct SessionMessageTransportSupportTestRunner {
    static func main() {
        assertMessageTransport(
            SessionMessageTransportSupport.transport(
                isInTmux: true,
                tty: "ttys001",
                sessionId: "session-1",
                allowsDetachedResume: false
            ) == .tmux(tty: "ttys001"),
            "tmux sessions should keep using pane messaging"
        )

        assertMessageTransport(
            SessionMessageTransportSupport.transport(
                isInTmux: false,
                tty: nil,
                sessionId: "session-2.jsonl",
                allowsDetachedResume: true
            ) == .detachedResume(sessionId: "session-2"),
            "detached resume should only be available when the caller explicitly opts in"
        )

        assertMessageTransport(
            SessionMessageTransportSupport.transport(
                isInTmux: false,
                tty: nil,
                sessionId: "session-2.jsonl",
                allowsDetachedResume: false
            ) == .unavailable,
            "live monitored sessions should not reuse detached resume because it collides with hook session identity"
        )

        assertMessageTransport(
            SessionMessageTransportSupport.transport(
                isInTmux: false,
                tty: nil,
                sessionId: nil,
                allowsDetachedResume: false
            ) == .unavailable,
            "sessions without tmux or a resume id should remain unavailable"
        )

        assertMessageTransport(
            SessionMessageTransportSupport.detachedThreadId(for: "session-2.jsonl") == "detached-session:session-2",
            "detached resume launches should normalize their process key"
        )

        print("session message transport support checks passed")
    }
}
