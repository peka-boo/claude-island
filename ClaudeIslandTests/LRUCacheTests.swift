import XCTest
@testable import ClaudeIsland

class LRUCacheTests: XCTestCase {
    var cache: LRUCache<String, Int>!
    
    override func setUp() {
        super.setUp()
        cache = LRUCache<String, Int>(capacity: 3)
    }
    
    override func tearDown() {
        cache = nil
        super.tearDown()
    }
    
    func testCacheCapacity() {
        // 设置超过容量的条目
        cache.set("key1", value: 1)
        cache.set("key2", value: 2)
        cache.set("key3", value: 3)
        cache.set("key4", value: 4) // 这应该淘汰key1
        
        XCTAssertNil(cache.get("key1"), "最久未使用的条目应该被淘汰")
        XCTAssertEqual(cache.get("key2"), 2, "key2应该仍然存在")
        XCTAssertEqual(cache.get("key3"), 3, "key3应该仍然存在")
        XCTAssertEqual(cache.get("key4"), 4, "key4应该存在")
    }
    
    func testLRUBehavior() {
        cache.set("key1", value: 1)
        cache.set("key2", value: 2)
        cache.set("key3", value: 3)
        
        // 访问key1，使其成为最近使用
        _ = cache.get("key1")
        
        // 添加新条目，应该淘汰key2（最久未使用）
        cache.set("key4", value: 4)
        
        XCTAssertNotNil(cache.get("key1"), "key1应该仍然存在（最近被访问）")
        XCTAssertNil(cache.get("key2"), "key2应该被淘汰（最久未使用）")
        XCTAssertEqual(cache.get("key3"), 3, "key3应该仍然存在")
        XCTAssertEqual(cache.get("key4"), 4, "key4应该存在")
    }
    
    func testRemove() {
        cache.set("key1", value: 1)
        cache.set("key2", value: 2)
        
        let removedValue = cache.remove("key1")
        XCTAssertEqual(removedValue, 1, "移除应该返回被移除的值")
        XCTAssertNil(cache.get("key1"), "移除后条目不应该存在")
        XCTAssertEqual(cache.count, 1, "移除后缓存计数应该减少")
    }
    
    func testUpdateExistingKey() {
        cache.set("key1", value: 1)
        cache.set("key1", value: 10) // 更新现有键
        
        XCTAssertEqual(cache.get("key1"), 10, "应该返回更新后的值")
        XCTAssertEqual(cache.count, 1, "更新不应该增加计数")
    }
    
    func testRemoveAll() {
        cache.set("key1", value: 1)
        cache.set("key2", value: 2)
        cache.set("key3", value: 3)
        
        cache.removeAll()
        
        XCTAssertEqual(cache.count, 0, "移除所有后计数应该为0")
        XCTAssertNil(cache.get("key1"), "所有条目都应该被移除")
        XCTAssertNil(cache.get("key2"), "所有条目都应该被移除")
        XCTAssertNil(cache.get("key3"), "所有条目都应该被移除")
    }
    
    func testAllKeysAndValues() {
        cache.set("key1", value: 1)
        cache.set("key2", value: 2)
        cache.set("key3", value: 3)
        
        let keys = cache.allKeys()
        let values = cache.allValues()
        
        XCTAssertEqual(keys.count, 3, "应该有3个键")
        XCTAssertEqual(values.count, 3, "应该有3个值")
        XCTAssertTrue(keys.contains("key1"), "键列表应该包含key1")
        XCTAssertTrue(values.contains(1), "值列表应该包含1")
    }
    
    func testThreadSafety() {
        let expectation = XCTestExpectation(description: "线程安全测试")
        let concurrentQueue = DispatchQueue(label: "test.concurrent", attributes: .concurrent)
        let group = DispatchGroup()
        
        // 并发访问缓存
        for i in 0..<100 {
            group.enter()
            concurrentQueue.async {
                self.cache.set("key\(i)", value: i)
                _ = self.cache.get("key\(i)")
                group.leave()
            }
        }
        
        group.notify(queue: .main) {
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 5.0)
        
        // 验证缓存状态一致
        XCTAssertLessThanOrEqual(self.cache.count, 3, "缓存不应该超过容量限制")
    }
}
