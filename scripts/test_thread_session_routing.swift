import Foundation

@inline(__always)
func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        fputs("Assertion failed: \(message)\n", stderr)
        exit(1)
    }
}

@main
struct ThreadSessionRoutingTestRunner {
    static func main() {
        expect(normalizeCLISessionId("abc123") == "abc123", "plain session ids should pass through")
        expect(normalizeCLISessionId("abc123.jsonl") == "abc123", "jsonl suffix should be stripped")
        expect(normalizeCLISessionId("  abc123.jsonl  ") == "abc123", "whitespace should be trimmed before normalization")
        expect(normalizeCLISessionId(nil) == nil, "nil session ids should stay nil")
        expect(normalizeCLISessionId("   ") == nil, "empty session ids should normalize to nil")

        expect(
            ThreadSessionRouter.route(isActiveProcess: true, cliSessionId: nil) == .sendToActiveProcess,
            "active processes should always receive follow-up input directly"
        )
        expect(
            ThreadSessionRouter.route(isActiveProcess: false, cliSessionId: "abc123") == .resumePersistedSession("abc123"),
            "persisted session ids should resume when there is no active process"
        )
        expect(
            ThreadSessionRouter.route(isActiveProcess: false, cliSessionId: "abc123.jsonl") == .resumePersistedSession("abc123"),
            "legacy jsonl-style session ids should normalize before resume"
        )
        expect(
            ThreadSessionRouter.route(isActiveProcess: false, cliSessionId: nil) == .startNewSession,
            "missing session ids should start a fresh session"
        )

        print("thread session routing checks passed")
    }
}
