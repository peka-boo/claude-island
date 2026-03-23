//
//  InteractivePromptDisplaySupport.swift
//  ClaudeIsland
//
//  Shared presentation routing for interactive Claude prompts.
//

import Foundation

enum InteractivePromptPresentation: Equatable, Sendable {
    case structuredAsk(AskUserQuestionPrompt)
    case freeformAsk
}

enum InteractivePromptDisplaySupport {
    static func presentation(
        toolName: String?,
        rawInput: [String: Any]?
    ) -> InteractivePromptPresentation? {
        guard toolName == "AskUserQuestion" else {
            return nil
        }

        if let rawInput,
           let prompt = AskUserQuestionPromptParser.parse(rawInput) {
            return .structuredAsk(prompt)
        }

        return .freeformAsk
    }
}
