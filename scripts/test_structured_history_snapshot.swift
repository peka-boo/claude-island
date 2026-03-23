import Foundation

func assertSnapshot(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        fputs("Assertion failed: \(message)\n", stderr)
        exit(1)
    }
}

@main
struct StructuredHistorySnapshotTestRunner {
    static func main() async throws {
        let tempHome = FileManager.default.temporaryDirectory
            .appendingPathComponent("claude-island-structured-history-\(UUID().uuidString)")
        let projectDir = tempHome.appendingPathComponent(".claude/projects/-tmp-demo")
        try FileManager.default.createDirectory(at: projectDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempHome) }

        let sessionURL = projectDir.appendingPathComponent("session-1.jsonl")
        let agentURL = projectDir.appendingPathComponent("agent-agent-1.jsonl")

        let sessionContent = """
        {"parentUuid":null,"isSidechain":false,"userType":"external","cwd":"/tmp/demo","sessionId":"session-1","version":"1.0.0","gitBranch":"main","type":"user","message":{"role":"user","content":"Please inspect the repo"},"uuid":"u1","timestamp":"2026-03-20T10:00:00.000Z"}
        {"parentUuid":"u1","isSidechain":false,"userType":"external","cwd":"/tmp/demo","sessionId":"session-1","version":"1.0.0","gitBranch":"main","type":"assistant","message":{"id":"msg1","role":"assistant","content":[{"type":"thinking","thinking":"Need to inspect files"},{"type":"text","text":"I will inspect the repo."},{"type":"tool_use","id":"tool-task","name":"Task","input":{"description":"Investigate issue"}}]},"uuid":"a1","timestamp":"2026-03-20T10:00:01.000Z"}
        {"parentUuid":"a1","isSidechain":false,"userType":"external","cwd":"/tmp/demo","sessionId":"session-1","version":"1.0.0","gitBranch":"main","type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"tool-task","content":"Agent finished","is_error":false}]},"toolUseResult":{"stdout":"Agent finished","stderr":"","agentId":"agent-1","status":"completed","result":"Agent finished"},"toolName":"Task","uuid":"u2","timestamp":"2026-03-20T10:00:02.000Z"}
        """
        try sessionContent.write(to: sessionURL, atomically: true, encoding: .utf8)

        let agentContent = """
        {"type":"assistant","message":{"content":[{"type":"tool_use","id":"subtool-1","name":"Read","input":{"file_path":"/tmp/demo/README.md"}}]},"timestamp":"2026-03-20T10:00:01.500Z"}
        {"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"subtool-1","content":"README content","is_error":false}]},"timestamp":"2026-03-20T10:00:01.700Z"}
        """
        try agentContent.write(to: agentURL, atomically: true, encoding: .utf8)

        setenv("HOME", tempHome.path, 1)

        let snapshot = await StructuredHistorySnapshotBuilder.load(
            sessionId: "session-1",
            cwd: "/tmp/demo"
        )

        assertSnapshot(snapshot.items.count == 4, "should render user, thinking, assistant, and task tool items")
        assertSnapshot(snapshot.items.contains(where: {
            if case .thinking(let text) = $0.type {
                return text.contains("Need to inspect files")
            }
            return false
        }), "should keep thinking block")

        guard let taskItem = snapshot.items.first(where: {
            if case .toolCall(let tool) = $0.type {
                return tool.name == "Task"
            }
            return false
        }) else {
            fputs("Assertion failed: missing task tool item\n", stderr)
            exit(1)
        }

        if case .toolCall(let tool) = taskItem.type {
            assertSnapshot(tool.status == .success, "task tool should be completed")
            assertSnapshot(tool.result?.contains("Agent finished") == true, "task result should be attached")
            assertSnapshot(tool.subagentTools.count == 1, "task should include parsed subagent tools")
            assertSnapshot(tool.subagentTools[0].name == "Read", "subagent tool name should match")
        }

        assertSnapshot(snapshot.agentDescriptions["agent-1"] == "Investigate issue", "agent description should map from task description")

        print("structured history snapshot checks passed")
    }
}
