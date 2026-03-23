import Foundation

func assert(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        fputs("Assertion failed: \(message)\n", stderr)
        exit(1)
    }
}

@main
struct ImportedSessionHistoryTestRunner {
    static func main() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("claude-island-import-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("session.jsonl")
        let jsonl = """
        {"parentUuid":null,"isSidechain":false,"userType":"external","cwd":"/tmp/demo","sessionId":"session-1","version":"1.0.0","gitBranch":"main","type":"user","message":{"role":"user","content":"First user prompt"},"uuid":"u1","timestamp":"2026-03-20T10:00:00.000Z"}
        {"parentUuid":"u1","isSidechain":false,"userType":"external","cwd":"/tmp/demo","sessionId":"session-1","version":"1.0.0","gitBranch":"main","type":"assistant","message":{"id":"msg1","role":"assistant","content":[{"type":"thinking","thinking":"Need to inspect files"},{"type":"text","text":"I will inspect the project."},{"type":"tool_use","id":"tool-1","name":"Read","input":{"file_path":"/tmp/demo/README.md"}}]},"uuid":"a1","timestamp":"2026-03-20T10:00:01.000Z"}
        {"parentUuid":"a1","isSidechain":false,"userType":"external","cwd":"/tmp/demo","sessionId":"session-1","version":"1.0.0","gitBranch":"main","type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"tool-1","content":"README content","is_error":false}]},"toolUseResult":{"stdout":"README content","stderr":""},"toolName":"Read","uuid":"u2","timestamp":"2026-03-20T10:00:02.000Z"}
        """
        try jsonl.write(to: fileURL, atomically: true, encoding: .utf8)

        let parsed = try ImportedSessionHistoryParser.parse(jsonlURL: fileURL)

        assert(parsed.firstMessage == "First user prompt", "should extract first user message")
        assert(parsed.messageRecords.count == 3, "should create user, assistant text, and tool record")

        let user = parsed.messageRecords[0]
        assert(user.role == .user, "first record should be user")
        assert(user.content == "First user prompt", "user content should match")

        let assistant = parsed.messageRecords[1]
        assert(assistant.role == .assistant, "second record should be assistant")
        assert(assistant.content == "I will inspect the project.", "assistant text should be preserved")
        assert(assistant.thinking == "Need to inspect files", "thinking should be preserved")

        let tool = parsed.messageRecords[2]
        assert(tool.role == .assistant, "tool record should be assistant role")
        assert(tool.toolName == "Read", "tool name should match")
        assert(tool.toolInput?.contains("README.md") == true, "tool input should include file path")
        assert(tool.toolResult?.contains("README content") == true, "tool result should be attached")

        assert(parsed.createdAt == user.createdAt, "createdAt should match first record")
        assert(parsed.updatedAt == tool.createdAt, "updatedAt should match last record")

        print("imported session history checks passed")
    }
}
