//
//  ChatMessagePaginationSupport.swift
//  ClaudeIsland
//
//  Pure pagination helpers for lazily loading chat transcripts.
//

import Foundation

/// 协议：要求类型有content属性
protocol HasContent {
    var content: String { get }
}

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
    static let minPageSize = 20
    static let maxPageSize = 150
    
    /// 计算基于消息内容长度的动态页面大小
    /// - Parameter averageMessageLength: 平均消息字符长度
    /// - Returns: 优化后的页面大小
    static func dynamicPageSize(averageMessageLength: Double) -> Int {
        // 基于平均消息长度调整页面大小
        // 长消息：减少页面大小以降低内存占用
        // 短消息：增加页面大小以提高加载效率
        let basePageSize = defaultPageSize
        
        if averageMessageLength <= 100 {
            // 短消息：可以加载更多
            return min(maxPageSize, Int(Double(basePageSize) * 1.5))
        } else if averageMessageLength <= 500 {
            // 中等长度：使用默认大小
            return basePageSize
        } else if averageMessageLength <= 1000 {
            // 长消息：减少页面大小
            return max(minPageSize, Int(Double(basePageSize) * 0.75))
        } else {
            // 非常长的消息：使用最小页面大小
            return minPageSize
        }
    }
    
    /// 计算基于消息数组的动态页面大小
    /// - Parameter messages: 消息数组（需要有content属性）
    /// - Returns: 优化后的页面大小
    static func dynamicPageSize<T: HasContent>(for messages: [T]) -> Int {
        guard !messages.isEmpty else { return defaultPageSize }
        
        let totalLength = messages.reduce(0) { $0 + $1.content.count }
        let averageLength = Double(totalLength) / Double(messages.count)
        
        return dynamicPageSize(averageMessageLength: averageLength)
    }
    
    /// 计算预加载的页面大小（通常比正常页面小）
    /// - Parameter averageMessageLength: 平均消息字符长度
    /// - Returns: 预加载页面大小
    static func preloadPageSize(averageMessageLength: Double) -> Int {
        let pageSize = dynamicPageSize(averageMessageLength: averageMessageLength)
        return max(minPageSize, Int(Double(pageSize) * 0.5))
    }

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
