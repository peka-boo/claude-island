import XCTest
@testable import ClaudeIsland

class ChatMessagePaginationSupportTests: XCTestCase {
    
    func testInitialVisibleCount() {
        let count = ChatMessagePaginationSupport.initialVisibleCount(totalCount: 120, pageSize: 80)
        XCTAssertEqual(count, 80, "初始可见数量应该等于页面大小")
        
        let smallCount = ChatMessagePaginationSupport.initialVisibleCount(totalCount: 50, pageSize: 80)
        XCTAssertEqual(smallCount, 50, "当总数小于页面大小时，应该返回总数")
        
        let zeroCount = ChatMessagePaginationSupport.initialVisibleCount(totalCount: 0, pageSize: 80)
        XCTAssertEqual(zeroCount, 0, "当总数为0时，应该返回0")
    }
    
    func testPaginationState() {
        let state = ChatMessagePaginationSupport.state(totalCount: 120, loadedItems: 80)
        XCTAssertEqual(state.loadedCount, 80, "已加载数量应该正确")
        XCTAssertTrue(state.hasOlderItems, "当已加载数量小于总数时，应该有更旧的项目")
        
        let fullState = ChatMessagePaginationSupport.state(totalCount: 120, loadedItems: 120)
        XCTAssertEqual(fullState.loadedCount, 120, "已加载数量应该正确")
        XCTAssertFalse(fullState.hasOlderItems, "当已加载数量等于总数时，不应该有更旧的项目")
        
        let emptyState = ChatMessagePaginationSupport.state(totalCount: 0, loadedItems: 0)
        XCTAssertEqual(emptyState.loadedCount, 0, "已加载数量应该为0")
        XCTAssertFalse(emptyState.hasOlderItems, "当总数为0时，不应该有更旧的项目")
    }
    
    func testMergeOlderPage() {
        struct TestItem: Identifiable, Equatable {
            let id: String
        }
        
        let existing = [
            TestItem(id: "m3"),
            TestItem(id: "m4")
        ]
        
        let older = [
            TestItem(id: "m1"),
            TestItem(id: "m2"),
            TestItem(id: "m3")
        ]
        
        let merged = ChatMessagePaginationSupport.mergeOlderPage(
            existingItems: existing,
            olderItems: older,
            totalCount: 4
        )
        
        XCTAssertEqual(merged.items.map(\.id), ["m1", "m2", "m3", "m4"], "应该按正确顺序合并，无重复")
        XCTAssertEqual(merged.loadedCount, 4, "已加载数量应该等于唯一项目数")
        XCTAssertFalse(merged.hasOlderItems, "当所有项目都已加载时，不应该有更旧的项目")
    }
    
    func testMergeOlderPageWithDuplicates() {
        struct TestItem: Identifiable, Equatable {
            let id: String
        }
        
        let existing = [
            TestItem(id: "m2"),
            TestItem(id: "m3")
        ]
        
        let older = [
            TestItem(id: "m1"),
            TestItem(id: "m2")
        ]
        
        let merged = ChatMessagePaginationSupport.mergeOlderPage(
            existingItems: existing,
            olderItems: older,
            totalCount: 3
        )
        
        XCTAssertEqual(merged.items.count, 3, "应该去除重复项")
        XCTAssertEqual(merged.items.map(\.id), ["m1", "m2", "m3"], "应该按正确顺序合并")
    }
    
    func testDynamicPageSize() {
        // 测试短消息
        let shortPageSize = ChatMessagePaginationSupport.dynamicPageSize(averageMessageLength: 50)
        XCTAssertGreaterThan(shortPageSize, 80, "短消息应该使用更大的页面大小")
        
        // 测试中等消息
        let mediumPageSize = ChatMessagePaginationSupport.dynamicPageSize(averageMessageLength: 300)
        XCTAssertEqual(mediumPageSize, 80, "中等消息应该使用默认页面大小")
        
        // 测试长消息
        let longPageSize = ChatMessagePaginationSupport.dynamicPageSize(averageMessageLength: 800)
        XCTAssertLessThan(longPageSize, 80, "长消息应该使用更小的页面大小")
        
        // 测试非常长的消息
        let veryLongPageSize = ChatMessagePaginationSupport.dynamicPageSize(averageMessageLength: 1500)
        XCTAssertEqual(veryLongPageSize, 20, "非常长的消息应该使用最小页面大小")
    }
    
    func testDynamicPageSizeWithMessages() {
        struct TestMessage: HasContent {
            let content: String
        }
        
        let shortMessages = [
            TestMessage(content: "短消息1"),
            TestMessage(content: "短消息2")
        ]
        
        let shortPageSize = ChatMessagePaginationSupport.dynamicPageSize(for: shortMessages)
        XCTAssertGreaterThan(shortPageSize, 80, "短消息数组应该使用更大的页面大小")
        
        let longMessages = [
            TestMessage(content: String(repeating: "长消息内容", count: 100)),
            TestMessage(content: String(repeating: "长消息内容", count: 100))
        ]
        
        let longPageSize = ChatMessagePaginationSupport.dynamicPageSize(for: longMessages)
        XCTAssertLessThan(longPageSize, 80, "长消息数组应该使用更小的页面大小")
    }
    
    func testPreloadPageSize() {
        let preloadSize = ChatMessagePaginationSupport.preloadPageSize(averageMessageLength: 300)
        XCTAssertLessThanOrEqual(preloadSize, 40, "预加载页面大小应该小于或等于正常页面大小的一半")
        
        let shortPreloadSize = ChatMessagePaginationSupport.preloadPageSize(averageMessageLength: 50)
        XCTAssertGreaterThan(shortPreloadSize, 0, "预加载页面大小应该大于0")
    }
}

// 协议用于测试dynamicPageSize
protocol HasContent {
    var content: String { get }
}
