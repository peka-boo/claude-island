//
//  AskUserQuestionSupport.swift
//  ClaudeIsland
//
//  Pure parsing and serialization helpers for AskUserQuestion prompts.
//

import Foundation

struct AskUserQuestionPrompt: Equatable, Sendable {
    let questions: [AskUserQuestionPromptItem]

    var isEmpty: Bool {
        questions.isEmpty
    }
}

struct AskUserQuestionPromptItem: Equatable, Sendable, Identifiable {
    let question: String
    let header: String?
    let multiSelect: Bool
    let options: [AskUserQuestionPromptOption]

    var id: String {
        question
    }
}

struct AskUserQuestionPromptOption: Equatable, Sendable, Identifiable {
    let rawLabel: String
    let displayLabel: String
    let description: String?
    let isRecommended: Bool

    var id: String {
        rawLabel
    }
}

struct AskUserQuestionDraftAnswer: Equatable, Sendable {
    let selectedOptionLabels: [String]
    let customAnswer: String?
    let notes: String?
}

struct AskUserQuestionAnswerAnnotation: Equatable, Sendable {
    let notes: String?
}

struct AskUserQuestionSubmission: Equatable, Sendable {
    let answers: [String: String]
    let annotations: [String: AskUserQuestionAnswerAnnotation]
    let responseText: String
}

struct AskUserQuestionWizardStep: Equatable, Sendable, Identifiable {
    enum Kind: Equatable, Sendable {
        case question(questionID: String)
        case submit
    }

    let index: Int
    let title: String
    let isComplete: Bool
    let kind: Kind

    var id: String {
        switch kind {
        case .question(let questionID):
            return "question-\(questionID)"
        case .submit:
            return "submit"
        }
    }
}

enum AskUserQuestionPromptParser {
    nonisolated static func parse(_ rawInput: [String: Any]) -> AskUserQuestionPrompt? {
        guard let rawQuestions = rawInput["questions"] as? [Any] else {
            return nil
        }

        let questions = rawQuestions.compactMap { rawQuestion -> AskUserQuestionPromptItem? in
            guard let questionDict = rawQuestion as? [String: Any],
                  let question = trimmedString(questionDict["question"]),
                  !question.isEmpty else {
                return nil
            }

            let rawOptions = questionDict["options"] as? [Any] ?? []
            let options = rawOptions.compactMap { rawOption -> AskUserQuestionPromptOption? in
                guard let optionDict = rawOption as? [String: Any],
                      let rawLabel = trimmedString(optionDict["label"]),
                      !rawLabel.isEmpty else {
                    return nil
                }

                let hasRecommendedSuffix = rawLabel.hasSuffix(" (Recommended)")
                let isRecommended = boolValue(optionDict["recommended"])
                    ?? boolValue(optionDict["isRecommended"])
                    ?? hasRecommendedSuffix

                return AskUserQuestionPromptOption(
                    rawLabel: rawLabel,
                    displayLabel: displayLabel(from: rawLabel),
                    description: trimmedString(optionDict["description"]),
                    isRecommended: isRecommended
                )
            }

            return AskUserQuestionPromptItem(
                question: question,
                header: trimmedString(questionDict["header"]),
                multiSelect: boolValue(questionDict["multiSelect"]) ?? false,
                options: options
            )
        }

        guard !questions.isEmpty else {
            return nil
        }

        return AskUserQuestionPrompt(questions: questions)
    }

    nonisolated private static func displayLabel(from rawLabel: String) -> String {
        if rawLabel.hasSuffix(" (Recommended)") {
            return String(rawLabel.dropLast(" (Recommended)".count))
        }
        return rawLabel
    }
}

enum AskUserQuestionSubmissionBuilder {
    nonisolated static func build(
        prompt: AskUserQuestionPrompt,
        drafts: [String: AskUserQuestionDraftAnswer]
    ) -> AskUserQuestionSubmission? {
        var answers: [String: String] = [:]
        var annotations: [String: AskUserQuestionAnswerAnnotation] = [:]
        var responseSegments: [String] = []

        for question in prompt.questions {
            guard let draft = drafts[question.question] else { continue }

            let selectedLabels = normalizeSelectedLabels(draft.selectedOptionLabels, multiSelect: question.multiSelect)
            let customAnswer = trimmed(draft.customAnswer)
            let notes = trimmed(draft.notes)

            let answerComponents: [String]
            if question.multiSelect {
                answerComponents = selectedLabels + (customAnswer.map { [$0] } ?? [])
            } else if let customAnswer, !customAnswer.isEmpty {
                answerComponents = [customAnswer]
            } else {
                answerComponents = selectedLabels
            }

            let answerText: String?
            if !answerComponents.isEmpty {
                answerText = answerComponents.joined(separator: ", ")
            } else {
                answerText = notes
            }

            guard let answerText, !answerText.isEmpty else { continue }

            answers[question.question] = answerText

            let annotationText = notes ?? ((selectedLabels.isEmpty && customAnswer != nil) ? customAnswer : nil)
            if let annotationText, !annotationText.isEmpty {
                annotations[question.question] = AskUserQuestionAnswerAnnotation(notes: annotationText)
            }

            responseSegments.append(serializedResponseSegment(
                question: question.question,
                answer: answerText,
                notes: annotations[question.question]?.notes
            ))
        }

        guard !answers.isEmpty else {
            return nil
        }

        return AskUserQuestionSubmission(
            answers: answers,
            annotations: annotations,
            responseText: responseSegments.joined(separator: ", ")
        )
    }

    nonisolated private static func normalizeSelectedLabels(_ labels: [String], multiSelect: Bool) -> [String] {
        var normalized: [String] = []
        var seen = Set<String>()

        for label in labels {
            let trimmed = trimmed(label)
            guard let trimmed, !trimmed.isEmpty, !seen.contains(trimmed) else { continue }
            normalized.append(trimmed)
            seen.insert(trimmed)
            if !multiSelect {
                break
            }
        }

        return normalized
    }

    nonisolated private static func serializedResponseSegment(
        question: String,
        answer: String,
        notes: String?
    ) -> String {
        var segment = "\"\(escaped(question))\"=\"\(escaped(answer))\""
        if let notes, !notes.isEmpty {
            segment += " user notes: \(notes)"
        }
        return segment
    }

    nonisolated private static func escaped(_ value: String) -> String {
        value.replacingOccurrences(of: "\"", with: "\\\"")
    }
}

enum AskUserQuestionWizardSupport {
    nonisolated static func steps(
        prompt: AskUserQuestionPrompt,
        drafts: [String: AskUserQuestionDraftAnswer]
    ) -> [AskUserQuestionWizardStep] {
        let questionSteps = prompt.questions.enumerated().map { index, question in
            AskUserQuestionWizardStep(
                index: index,
                title: stepTitle(for: question, index: index),
                isComplete: canAdvance(question: question, draft: drafts[question.question]),
                kind: .question(questionID: question.question)
            )
        }

        let submitStep = AskUserQuestionWizardStep(
            index: prompt.questions.count,
            title: "Submit",
            isComplete: questionSteps.allSatisfy(\.isComplete),
            kind: .submit
        )

        return questionSteps + [submitStep]
    }

    nonisolated static func initialStepIndex(
        prompt: AskUserQuestionPrompt,
        drafts: [String: AskUserQuestionDraftAnswer]
    ) -> Int {
        let steps = steps(prompt: prompt, drafts: drafts)
        return steps.firstIndex(where: { !$0.isComplete }) ?? max(steps.count - 1, 0)
    }

    nonisolated static func canAdvance(
        question: AskUserQuestionPromptItem,
        draft: AskUserQuestionDraftAnswer?
    ) -> Bool {
        answerText(question: question, draft: draft) != nil
    }

    nonisolated static func answerText(
        question: AskUserQuestionPromptItem,
        draft: AskUserQuestionDraftAnswer?
    ) -> String? {
        guard let draft else { return nil }

        let selectedLabels = normalizeSelectedLabels(
            draft.selectedOptionLabels,
            multiSelect: question.multiSelect
        )
        let customAnswer = trimmed(draft.customAnswer)
        let notes = trimmed(draft.notes)

        let answerComponents: [String]
        if question.multiSelect {
            answerComponents = selectedLabels + (customAnswer.map { [$0] } ?? [])
        } else if let customAnswer, !customAnswer.isEmpty {
            answerComponents = [customAnswer]
        } else {
            answerComponents = selectedLabels
        }

        if !answerComponents.isEmpty {
            return answerComponents.joined(separator: ", ")
        }

        return notes
    }

    nonisolated static func stepTitle(
        for question: AskUserQuestionPromptItem,
        index: Int
    ) -> String {
        if let header = trimmed(question.header) {
            return header
        }
        return "Question \(index + 1)"
    }

    nonisolated private static func normalizeSelectedLabels(
        _ labels: [String],
        multiSelect: Bool
    ) -> [String] {
        var normalized: [String] = []
        var seen = Set<String>()

        for label in labels {
            guard let cleaned = trimmed(label), !seen.contains(cleaned) else { continue }
            normalized.append(cleaned)
            seen.insert(cleaned)
            if !multiSelect {
                break
            }
        }

        return normalized
    }
}

nonisolated private func trimmedString(_ value: Any?) -> String? {
    guard let string = value as? String else {
        return nil
    }
    let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
}

nonisolated private func boolValue(_ value: Any?) -> Bool? {
    switch value {
    case let bool as Bool:
        return bool
    case let string as String:
        switch string.lowercased() {
        case "true": return true
        case "false": return false
        default: return nil
        }
    default:
        return nil
    }
}

nonisolated private func trimmed(_ value: String?) -> String? {
    guard let value else { return nil }
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
}
