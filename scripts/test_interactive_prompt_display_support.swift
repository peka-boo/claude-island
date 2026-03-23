import Foundation

@inline(__always)
func assertInteractivePrompt(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        fputs("Assertion failed: \(message)\n", stderr)
        exit(1)
    }
}

@main
struct InteractivePromptDisplaySupportTestRunner {
    static func main() {
        let askPromptInput: [String: Any] = [
            "questions": [
                [
                    "question": "Choose next step",
                    "header": "Action",
                    "multiSelect": false,
                    "options": [
                        [
                            "label": "Build app",
                            "description": "Compile ClaudeIsland"
                        ],
                        [
                            "label": "Open Xcode",
                            "description": "Inspect project files"
                        ]
                    ]
                ]
            ]
        ]

        guard let structuredPresentation = InteractivePromptDisplaySupport.presentation(
            toolName: "AskUserQuestion",
            rawInput: askPromptInput
        ) else {
            fputs("Assertion failed: structured AskUserQuestion prompt should produce a presentation\n", stderr)
            exit(1)
        }

        switch structuredPresentation {
        case .structuredAsk(let prompt):
            assertInteractivePrompt(prompt.questions.count == 1, "structured presentation should preserve parsed questions")
            assertInteractivePrompt(prompt.questions[0].header == "Action", "structured prompt should preserve headers")
        case .freeformAsk:
            fputs("Assertion failed: structured AskUserQuestion prompt should not fall back to freeform\n", stderr)
            exit(1)
        }

        assertInteractivePrompt(
            InteractivePromptDisplaySupport.presentation(
                toolName: "AskUserQuestion",
                rawInput: ["message": "Need a freeform reply"]
            ) == .freeformAsk,
            "AskUserQuestion without structured questions should use the freeform reply UI"
        )

        assertInteractivePrompt(
            InteractivePromptDisplaySupport.presentation(
                toolName: "Bash",
                rawInput: askPromptInput
            ) == nil,
            "non-interactive tools should not produce an AskUserQuestion presentation"
        )

        print("interactive prompt display support checks passed")
    }
}
