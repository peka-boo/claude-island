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
    nonisolated static let streamingAutoScrollMinimumInterval: TimeInterval = 0.12

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

    nonisolated static func streamingScrollAction(
        hasAppliedInitialPosition: Bool,
        elapsedSinceLastAutoScroll: TimeInterval?,
        minimumInterval: TimeInterval = ChatTranscriptScrollSupport.streamingAutoScrollMinimumInterval
    ) -> ChatTranscriptScrollAction {
        guard hasAppliedInitialPosition else {
            return .none
        }

        guard let elapsedSinceLastAutoScroll else {
            return .jumpToLatest
        }

        return elapsedSinceLastAutoScroll >= minimumInterval ? .jumpToLatest : .none
    }
}
