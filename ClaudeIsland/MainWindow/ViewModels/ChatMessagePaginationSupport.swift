//
//  ChatMessagePaginationSupport.swift
//  ClaudeIsland
//
//  Pure pagination helpers for lazily loading chat transcripts.
//

import Foundation

struct ChatPaginationState: Equatable, Sendable {
    let loadedCount: Int
    let hasOlderItems: Bool
}

struct PaginatedChatItems<Item: Identifiable & Equatable>: Equatable where Item.ID: Hashable {
    let items: [Item]
    let state: ChatPaginationState

    var loadedCount: Int { state.loadedCount }
    var hasOlderItems: Bool { state.hasOlderItems }
}

enum ChatMessagePaginationSupport {
    static let defaultPageSize = 80

    static func initialVisibleCount(
        totalCount: Int,
        pageSize: Int = defaultPageSize
    ) -> Int {
        max(0, min(totalCount, pageSize))
    }

    static func state(
        totalCount: Int,
        loadedItems: Int
    ) -> ChatPaginationState {
        let clampedLoadedCount = max(0, loadedItems)
        return ChatPaginationState(
            loadedCount: clampedLoadedCount,
            hasOlderItems: clampedLoadedCount < max(0, totalCount)
        )
    }

    static func mergeOlderPage<Item: Identifiable & Equatable>(
        existingItems: [Item],
        olderItems: [Item],
        totalCount: Int
    ) -> PaginatedChatItems<Item> where Item.ID: Hashable {
        var seen = Set<Item.ID>()
        var merged: [Item] = []

        for item in olderItems + existingItems {
            if seen.insert(item.id).inserted {
                merged.append(item)
            }
        }

        return PaginatedChatItems(
            items: merged,
            state: state(
                totalCount: totalCount,
                loadedItems: merged.count
            )
        )
    }
}
