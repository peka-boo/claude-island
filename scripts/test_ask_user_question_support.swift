import Foundation

func assertAskUserQuestion(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        fputs("Assertion failed: \(message)\n", stderr)
        exit(1)
    }
}

@main
struct AskUserQuestionSupportTestRunner {
    static func main() {
        let rawPrompt: [String: Any] = [
            "questions": [
                [
                    "question": "Pick rollout scope",
                    "header": "Scope",
                    "multiSelect": true,
                    "options": [
                        [
                            "label": "UI polish (Recommended)",
                            "description": "Tighten layout and spacing"
                        ],
                        [
                            "label": "Session fixes",
                            "description": "Repair session restore"
                        ],
                        [
                            "label": "Claude hooks",
                            "description": "Finish permission support",
                            "recommended": true
                        ]
                    ]
                ],
                [
                    "question": "Need a rename migration?",
                    "header": "Migration",
                    "multiSelect": false,
                    "options": [
                        [
                            "label": "Yes",
                            "description": "Rename old titles during import"
                        ],
                        [
                            "label": "No",
                            "description": "Keep existing names"
                        ]
                    ]
                ],
                [
                    "question": "What extra follow-up should we queue?",
                    "multiSelect": true,
                    "options": [
                        [
                            "label": "Approval UI"
                        ],
                        [
                            "label": "Streaming fixes"
                        ]
                    ]
                ]
            ]
        ]

        guard let prompt = AskUserQuestionPromptParser.parse(rawPrompt) else {
            fputs("Assertion failed: prompt should parse\n", stderr)
            exit(1)
        }

        assertAskUserQuestion(prompt.questions.count == 3, "should parse all questions")
        assertAskUserQuestion(prompt.questions[0].multiSelect, "first question should be multi-select")
        assertAskUserQuestion(prompt.questions[1].multiSelect == false, "second question should be single-select")
        assertAskUserQuestion(prompt.questions[0].options[0].displayLabel == "UI polish", "recommended suffix should be trimmed for display")
        assertAskUserQuestion(prompt.questions[0].options[0].rawLabel == "UI polish (Recommended)", "raw label should be preserved")
        assertAskUserQuestion(prompt.questions[0].options[0].isRecommended, "recommended suffix should mark option as recommended")
        assertAskUserQuestion(prompt.questions[0].options[2].isRecommended, "explicit recommended flag should be parsed")

        let drafts: [String: AskUserQuestionDraftAnswer] = [
            "Pick rollout scope": AskUserQuestionDraftAnswer(
                selectedOptionLabels: ["UI polish (Recommended)", "Claude hooks"],
                customAnswer: nil,
                notes: "Focus on the main window first"
            ),
            "Need a rename migration?": AskUserQuestionDraftAnswer(
                selectedOptionLabels: [],
                customAnswer: "No, keep titles stable",
                notes: nil
            ),
            "What extra follow-up should we queue?": AskUserQuestionDraftAnswer(
                selectedOptionLabels: ["Approval UI"],
                customAnswer: "Retry stuck replies",
                notes: nil
            )
        ]

        guard let submission = AskUserQuestionSubmissionBuilder.build(prompt: prompt, drafts: drafts) else {
            fputs("Assertion failed: submission should be created\n", stderr)
            exit(1)
        }

        assertAskUserQuestion(
            submission.answers["Pick rollout scope"] == "UI polish (Recommended), Claude hooks",
            "selected options should be serialized in order"
        )
        assertAskUserQuestion(
            submission.annotations["Pick rollout scope"]?.notes == "Focus on the main window first",
            "notes should be attached as annotations"
        )
        assertAskUserQuestion(
            submission.answers["Need a rename migration?"] == "No, keep titles stable",
            "custom answer should become the answer text"
        )
        assertAskUserQuestion(
            submission.annotations["Need a rename migration?"]?.notes == "No, keep titles stable",
            "custom answer-only replies should preserve notes for history parity"
        )
        assertAskUserQuestion(
            submission.answers["What extra follow-up should we queue?"] == "Approval UI, Retry stuck replies",
            "multi-select custom answers should be appended to selected options"
        )
        assertAskUserQuestion(
            submission.responseText.contains("\"Pick rollout scope\"=\"UI polish (Recommended), Claude hooks\""),
            "response text should include the first answer"
        )
        assertAskUserQuestion(
            submission.responseText.contains("user notes: Focus on the main window first"),
            "response text should include notes"
        )
        assertAskUserQuestion(
            submission.responseText.contains("\"Need a rename migration?\"=\"No, keep titles stable\""),
            "response text should include custom answers"
        )

        let emptySubmission = AskUserQuestionSubmissionBuilder.build(prompt: prompt, drafts: [:])
        assertAskUserQuestion(emptySubmission == nil, "empty draft should not create a submission")

        let wizardSteps = AskUserQuestionWizardSupport.steps(prompt: prompt, drafts: drafts)
        assertAskUserQuestion(wizardSteps.count == 4, "wizard should include every question plus a submit step")
        assertAskUserQuestion(wizardSteps[0].title == "Scope", "wizard should prefer question header as the step title")
        assertAskUserQuestion(wizardSteps[1].title == "Migration", "wizard should preserve later headers")
        assertAskUserQuestion(wizardSteps[2].title == "Question 3", "wizard should fall back to a numbered title when header is missing")
        assertAskUserQuestion(wizardSteps[3].title == "Submit", "wizard should end with a submit step")
        assertAskUserQuestion(wizardSteps[0].isComplete, "answered question steps should be marked complete")
        assertAskUserQuestion(wizardSteps[3].isComplete, "submit step should be marked complete once every question has an answer")

        let partialDrafts: [String: AskUserQuestionDraftAnswer] = [
            "Pick rollout scope": AskUserQuestionDraftAnswer(
                selectedOptionLabels: ["Claude hooks"],
                customAnswer: nil,
                notes: nil
            )
        ]
        let partialSteps = AskUserQuestionWizardSupport.steps(prompt: prompt, drafts: partialDrafts)
        assertAskUserQuestion(partialSteps[0].isComplete, "partially answered wizard should keep completed steps")
        assertAskUserQuestion(partialSteps[1].isComplete == false, "unanswered later questions should stay incomplete")
        assertAskUserQuestion(partialSteps[3].isComplete == false, "submit step should stay incomplete until all questions are answered")
        assertAskUserQuestion(
            AskUserQuestionWizardSupport.initialStepIndex(prompt: prompt, drafts: partialDrafts) == 1,
            "wizard should jump to the first unanswered question"
        )
        assertAskUserQuestion(
            AskUserQuestionWizardSupport.initialStepIndex(prompt: prompt, drafts: drafts) == 3,
            "wizard should open on submit when every question already has an answer"
        )
        assertAskUserQuestion(
            AskUserQuestionWizardSupport.canAdvance(
                question: prompt.questions[1],
                draft: drafts["Need a rename migration?"]
            ),
            "single-select custom answers should count as complete"
        )
        assertAskUserQuestion(
            AskUserQuestionWizardSupport.canAdvance(
                question: prompt.questions[2],
                draft: nil
            ) == false,
            "missing draft should not allow moving to the next step"
        )

        print("ask user question support checks passed")
    }
}
