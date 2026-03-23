//
//  ChatTranscriptScrollSupport.swift
//  ClaudeIsland
//
//  Pure helpers for deciding when transcript views should jump or animate.
//

import Foundation

enum ChatTranscriptScrollAction: Equatable {
    case none
    case jumpToLatest
    case animateToLatest
}

enum ChatTranscriptScrollSupport {
    nonisolated static let bottomAnchorID = "transcript-bottom-anchor"

    nonisolated static func scrollAction<Item: Identifiable & Equatable>(
        oldItems: [Item],
        newItems: [Item],
        hasAppliedInitialPosition: Bool
    ) -> ChatTranscriptScrollAction where Item.ID: Equatable {
        guard !newItems.isEmpty else {
            return .none
        }

        if !hasAppliedInitialPosition {
            return .jumpToLatest
        }

        if oldItems.isEmpty {
            return .jumpToLatest
        }

        return oldItems.last?.id != newItems.last?.id ? .animateToLatest : .none
    }

    nonisolated static func bottomScrollTarget(hasVisibleContent: Bool) -> String? {
        hasVisibleContent ? bottomAnchorID : nil
    }
}
