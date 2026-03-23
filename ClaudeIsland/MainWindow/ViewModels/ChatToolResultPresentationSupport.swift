//
//  ChatToolResultPresentationSupport.swift
//  ClaudeIsland
//
//  Presentation rules for long raw tool outputs in the main-window chat transcript.
//

import Foundation

enum ChatToolResultKind: Equatable, Sendable {
    case fileContent
    case toolOutput
}

struct ChatToolResultPresentation: Equatable, Sendable {
    let fullText: String
    let previewText: String
    let lineCount: Int
    let previewLineCount: Int
    let hiddenLineCount: Int
    let kind: ChatToolResultKind
    let shouldCollapse: Bool

    var collapseTitle: String {
        switch kind {
        case .fileContent:
            return "File Content"
        case .toolOutput:
            return "Large Output"
        }
    }
}

enum ChatToolResultPresentationSupport {
    static let previewLineLimit = 8
    static let collapseLineThreshold = 12
    static let previewCharacterLimit = 500
    static let collapseCharacterThreshold = 900

    static func presentation(for rawResult: String) -> ChatToolResultPresentation {
        let normalized = rawResult.trimmingCharacters(in: .newlines)
        let lines = normalized.components(separatedBy: "\n")
        let previewLines = Array(lines.prefix(previewLineLimit))
        let previewText = clampedPreviewText(from: previewLines.joined(separator: "\n"))
        let shouldCollapse = lines.count > collapseLineThreshold || normalized.count > collapseCharacterThreshold
        let kind = classify(lines: lines)

        return ChatToolResultPresentation(
            fullText: normalized,
            previewText: shouldCollapse ? previewText : normalized,
            lineCount: lines.count,
            previewLineCount: min(previewLines.count, previewLineLimit),
            hiddenLineCount: max(0, lines.count - previewLineLimit),
            kind: kind,
            shouldCollapse: shouldCollapse
        )
    }

    private static func clampedPreviewText(from preview: String) -> String {
        guard preview.count > previewCharacterLimit else { return preview }
        return String(preview.prefix(previewCharacterLimit)) + "…"
    }

    private static func classify(lines: [String]) -> ChatToolResultKind {
        let fileIndicators = [
            "import ", "func ", "let ", "var ", "struct ", "class ",
            "enum ", "protocol ", "extension ", "{", "}", " = "
        ]
        let indicatorMatches = lines.prefix(12).filter { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            return fileIndicators.contains { trimmed.contains($0) }
        }.count

        return indicatorMatches >= 3 ? .fileContent : .toolOutput
    }
}
