import Foundation

func assertCLIPermission(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        fputs("Assertion failed: \(message)\n", stderr)
        exit(1)
    }
}

@main
struct CLIPermissionFallbackTestRunner {
    static func main() {
        let parser = CLIStreamParser()
        let userToolResultLine = #"{"type":"user","message":{"role":"user","content":[{"type":"tool_result","content":"This command requires approval","is_error":true,"tool_use_id":"call_b03723010dd74934b6dfce2b"}]}}"#
        let parsedUserEvents = parser.parseLine(userToolResultLine)

        assertCLIPermission(parsedUserEvents.count == 1, "user tool_result stream line should produce one event")
        if case .toolResult(let parsedId, _, let parsedOutput) = parsedUserEvents[0] {
            assertCLIPermission(parsedId == "call_b03723010dd74934b6dfce2b", "parser should preserve the tool_use_id")
            assertCLIPermission(parsedOutput == "This command requires approval", "parser should preserve approval failure output")
        } else {
            fputs("Assertion failed: user tool_result line should parse as toolResult\n", stderr)
            exit(1)
        }

        var tracker = CLIPermissionFallbackTracker()
        let originalPrompt = "执行 iterm2 . 命令行"

        tracker.consume(
            .toolUse(
                id: "call_b03723010dd74934b6dfce2b",
                name: "Bash",
                input: "{\"command\":\"open -a iTerm .\",\"description\":\"在 iTerm2 中打开当前目录\"}"
            ),
            originalPrompt: originalPrompt,
            cliSessionId: "session-123"
        )

        for event in parsedUserEvents {
            tracker.consume(
                event,
                originalPrompt: originalPrompt,
                cliSessionId: "session-123"
            )
        }

        guard let pending = tracker.pendingRequest else {
            fputs("Assertion failed: pending approval should be synthesized\n", stderr)
            exit(1)
        }

        assertCLIPermission(pending.toolName == "Bash", "tool name should come from the preceding tool use")
        assertCLIPermission(
            pending.formattedInput?.contains("command: open -a iTerm .") == true,
            "formatted input should include the command"
        )
        assertCLIPermission(
            pending.formattedInput?.contains("description: 在 iTerm2 中打开当前目录") == true,
            "formatted input should include the description"
        )
        assertCLIPermission(
            pending.retryPrompt.contains("The user approved the pending Bash tool request."),
            "retry prompt should explain the approval"
        )
        assertCLIPermission(
            pending.retryPrompt.contains(originalPrompt),
            "retry prompt should preserve the original user request"
        )
        assertCLIPermission(
            pending.cliSessionId == "session-123",
            "retry request should keep the current Claude session id"
        )

        tracker.clearPendingRequest()
        assertCLIPermission(tracker.pendingRequest == nil, "clearing pending approval should remove synthesized state")

        var noApprovalTracker = CLIPermissionFallbackTracker()
        noApprovalTracker.consume(
            .toolUse(id: "call_ok", name: "Bash", input: "{\"command\":\"pwd\"}"),
            originalPrompt: "pwd",
            cliSessionId: nil
        )
        noApprovalTracker.consume(
            .toolResult(id: "call_ok", name: "Bash", output: "/Users/mac/Code/GITHUB/---/claude-island"),
            originalPrompt: "pwd",
            cliSessionId: nil
        )
        assertCLIPermission(
            noApprovalTracker.pendingRequest == nil,
            "normal tool results should not create pending approval state"
        )

        var writePermissionTracker = CLIPermissionFallbackTracker()
        writePermissionTracker.consume(
            .toolUse(
                id: "call_write",
                name: "Write",
                input: #"{"file_path":"/Users/mac/Code/GITHUB/NeoPanel/123.txt","content":"123\n"}"#
            ),
            originalPrompt: "执行。cat. 123>> 123.txt",
            cliSessionId: "session-write"
        )
        writePermissionTracker.consume(
            .toolResult(
                id: "call_write",
                name: "",
                output: "Claude requested permissions to write to /Users/mac/Code/GITHUB/NeoPanel/123.txt, but you haven't granted it yet."
            ),
            originalPrompt: "执行。cat. 123>> 123.txt",
            cliSessionId: "session-write"
        )
        assertCLIPermission(
            writePermissionTracker.pendingRequest?.toolName == "Write",
            "write permission failures should produce a local approval card"
        )
        assertCLIPermission(
            writePermissionTracker.pendingRequest?.formattedInput?.contains("file_path: /Users/mac/Code/GITHUB/NeoPanel/123.txt") == true,
            "write permission fallback should keep the target path"
        )

        var readPermissionTracker = CLIPermissionFallbackTracker()
        readPermissionTracker.consume(
            .toolUse(
                id: "call_read",
                name: "Read",
                input: #"{"file_path":"/Users/mac/.claude/settings.json"}"#
            ),
            originalPrompt: "读取 ~/.claude/settings.json",
            cliSessionId: "session-read"
        )
        readPermissionTracker.consume(
            .toolResult(
                id: "call_read",
                name: "",
                output: "Claude requested permissions to read from /Users/mac/.claude/settings.json, but you haven't granted it yet."
            ),
            originalPrompt: "读取 ~/.claude/settings.json",
            cliSessionId: "session-read"
        )
        assertCLIPermission(
            readPermissionTracker.pendingRequest?.toolName == "Read",
            "read permission failures should produce a local approval card"
        )

        var multiOperationTracker = CLIPermissionFallbackTracker()
        multiOperationTracker.consume(
            .toolUse(
                id: "call_multi",
                name: "Bash",
                input: #"{"command":"cat ~/.claude/settings.json 2>/dev/null | head -100","description":"Check Claude Code settings"}"#
            ),
            originalPrompt: "检查设置",
            cliSessionId: "session-multi"
        )
        multiOperationTracker.consume(
            .toolResult(
                id: "call_multi",
                name: "",
                output: "This Bash command contains multiple operations. The following part requires approval: cat ~/.claude/settings.json 2> /dev/null"
            ),
            originalPrompt: "检查设置",
            cliSessionId: "session-multi"
        )
        assertCLIPermission(
            multiOperationTracker.pendingRequest?.toolName == "Bash",
            "multi-operation bash approval failures should produce a local approval card"
        )

        var askUserQuestionTracker = CLIPermissionFallbackTracker()
        askUserQuestionTracker.consume(
            .toolUse(
                id: "call_question",
                name: "AskUserQuestion",
                input: #"{"questions":[{"header":"主题选择","question":"你想从哪个方向探索 ClaudeIsland 项目？","multiSelect":false,"options":[{"label":"功能开发","description":"添加新功能或增强现有模块"},{"label":"代码重构","description":"优化架构、清理代码、提升可维护性"}]}]}"#
            ),
            originalPrompt: "先让我选择方向",
            cliSessionId: "session-question"
        )
        assertCLIPermission(
            askUserQuestionTracker.pendingRequest?.toolName == "AskUserQuestion",
            "ask user question tool uses should create a local interactive prompt fallback"
        )
        assertCLIPermission(
            askUserQuestionTracker.pendingRequest?.toolInputJSON.contains("主题选择") == true,
            "ask user question fallback should preserve structured prompt input"
        )

        askUserQuestionTracker.consume(
            .toolResult(
                id: "call_question",
                name: "",
                output: "Answer questions?"
            ),
            originalPrompt: "先让我选择方向",
            cliSessionId: "session-question"
        )
        assertCLIPermission(
            askUserQuestionTracker.pendingRequest?.toolUseId == "call_question",
            "ask user question awaiting-response errors should keep the interactive prompt open"
        )

        let followUpPrompt = CLIPermissionFallbackTracker.makeAskUserQuestionFollowUpPrompt(
            #""你想从哪个方向探索 ClaudeIsland 项目？"="代码重构""#
        )
        assertCLIPermission(
            followUpPrompt.contains("User has answered your questions:"),
            "ask user question follow-up prompt should mirror Claude tool result phrasing"
        )
        assertCLIPermission(
            followUpPrompt.contains(#""你想从哪个方向探索 ClaudeIsland 项目？"="代码重构""#),
            "ask user question follow-up prompt should preserve the serialized answers"
        )

        askUserQuestionTracker.consume(
            .toolResult(
                id: "call_question",
                name: "",
                output: #"User has answered your questions: "你想从哪个方向探索 ClaudeIsland 项目？"="代码重构". You can now continue with the user's answers in mind."#
            ),
            originalPrompt: "先让我选择方向",
            cliSessionId: "session-question"
        )
        assertCLIPermission(
            askUserQuestionTracker.pendingRequest == nil,
            "completed ask user question results should clear the local interactive prompt"
        )

        print("cli permission fallback checks passed")
    }
}
