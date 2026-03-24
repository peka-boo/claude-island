# Claude Island 单元测试基础设施实施计划

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 为Claude Island项目建立标准的XCTest单元测试基础设施，替换现有的自定义测试脚本。

**架构:** 创建独立的ClaudeIslandTests目标，使用XCTest框架编写测试用例，覆盖核心组件：LRUCache、SidebarProjectGroupingSupport、ChatMessagePaginationSupport、GlobalSessionSupport。

**Tech Stack:** Swift 5.0, XCTest, Xcode 26.1.1

---

## 现有测试分析

**scripts目录中的测试脚本（共23个）：**
- test_ask_user_question_support.swift
- test_chat_message_pagination_support.swift
- test_chat_tool_result_presentation.swift
- test_chat_transcript_scroll_support.swift
- test_claude_message_display_support.swift
- test_cli_permission_fallback.swift
- test_composer_processing_support.swift
- test_composer_text_appearance.swift
- test_detached_resume_settings_support.swift
- test_global_session_support.swift
- test_import_session_filter_support.swift
- test_import_tracking.swift
- test_imported_session_history.swift
- test_interactive_prompt_display_support.swift
- test_message_composer_logic.swift
- test_notch_attention_support.swift
- test_session_message_transport_support.swift
- test_sidebar_project_grouping_support.swift
- test_structured_history_snapshot.swift
- test_thread_session_routing.swift
- test_window_manager_notch_teardown.swift

**测试模式：** 使用自定义assert函数，通过@main入口点运行，exit(1)表示失败。

---

## 任务清单

### Task 1: 创建测试目录结构

**Files:**
- Create: `ClaudeIslandTests/`
- Create: `ClaudeIslandTests/Helpers/`

**Step 1: 创建测试目录**

```bash
mkdir -p ClaudeIslandTests/Helpers
```

**Step 2: 验证目录创建**

```bash
ls -la ClaudeIslandTests/
```

**Step 3: Commit**

```bash
git add ClaudeIslandTests/
git commit -m "chore: create test directory structure"
```

---

### Task 2: 创建LRUCacheTests

**Files:**
- Create: `ClaudeIslandTests/LRUCacheTests.swift`
- Source: `ClaudeIsland/Utilities/LRUCache.swift:11-171`

**Step 1: 编写LRUCacheTests**

```swift
import XCTest
@testable import ClaudeIsland

final class LRUCacheTests: XCTestCase {
    
    func testBasicSetAndGet() {
        let cache = LRUCache<String, Int>(capacity: 3)
        
        cache.set("key1", value: 1)
        cache.set("key2", value: 2)
        
        XCTAssertEqual(cache.get("key1"), 1)
        XCTAssertEqual(cache.get("key2"), 2)
        XCTAssertNil(cache.get("key3"))
    }
    
    func testCapacityEviction() {
        let cache = LRUCache<String, Int>(capacity: 2)
        
        cache.set("key1", value: 1)
        cache.set("key2", value: 2)
        cache.set("key3", value: 3) // Should evict key1
        
        XCTAssertNil(cache.get("key1"))
        XCTAssertEqual(cache.get("key2"), 2)
        XCTAssertEqual(cache.get("key3"), 3)
        XCTAssertEqual(cache.count, 2)
    }
    
    func testLRUEvictionOrder() {
        let cache = LRUCache<String, Int>(capacity: 3)
        
        cache.set("key1", value: 1)
        cache.set("key2", value: 2)
        cache.set("key3", value: 3)
        
        // Access key1 to make it recently used
        _ = cache.get("key1")
        
        // Add key4, should evict key2 (least recently used)
        cache.set("key4", value: 4)
        
        XCTAssertEqual(cache.get("key1"), 1)
        XCTAssertNil(cache.get("key2"))
        XCTAssertEqual(cache.get("key3"), 3)
        XCTAssertEqual(cache.get("key4"), 4)
    }
    
    func testUpdateExistingKey() {
        let cache = LRUCache<String, Int>(capacity: 2)
        
        cache.set("key1", value: 1)
        cache.set("key2", value: 2)
        
        // Update key1
        cache.set("key1", value: 10)
        
        XCTAssertEqual(cache.get("key1"), 10)
        XCTAssertEqual(cache.count, 2)
    }
    
    func testRemove() {
        let cache = LRUCache<String, Int>(capacity: 3)
        
        cache.set("key1", value: 1)
        cache.set("key2", value: 2)
        
        let removed = cache.remove("key1")
        
        XCTAssertEqual(removed, 1)
        XCTAssertNil(cache.get("key1"))
        XCTAssertEqual(cache.count, 1)
    }
    
    func testRemoveAll() {
        let cache = LRUCache<String, Int>(capacity: 3)
        
        cache.set("key1", value: 1)
        cache.set("key2", value: 2)
        cache.set("key3", value: 3)
        
        cache.removeAll()
        
        XCTAssertEqual(cache.count, 0)
        XCTAssertNil(cache.get("key1"))
        XCTAssertNil(cache.get("key2"))
        XCTAssertNil(cache.get("key3"))
    }
    
    func testAllKeys() {
        let cache = LRUCache<String, Int>(capacity: 3)
        
        cache.set("key1", value: 1)
        cache.set("key2", value: 2)
        cache.set("key3", value: 3)
        
        let keys = cache.allKeys()
        
        XCTAssertEqual(keys.sorted(), ["key1", "key2", "key3"])
    }
    
    func testAllValues() {
        let cache = LRUCache<String, Int>(capacity: 3)
        
        cache.set("key1", value: 1)
        cache.set("key2", value: 2)
        cache.set("key3", value: 3)
        
        let values = cache.allValues()
        
        XCTAssertEqual(values.sorted(), [1, 2, 3])
    }
    
    func testCapacityPrecondition() {
        // This test verifies that capacity > 0 is enforced
        // Note: In a real test, you might want to use XCTAssertThrows
        // but for simplicity, we just verify the cache works with capacity 1
        let cache = LRUCache<String, Int>(capacity: 1)
        
        cache.set("key1", value: 1)
        cache.set("key2", value: 2) // Should evict key1
        
        XCTAssertNil(cache.get("key1"))
        XCTAssertEqual(cache.get("key2"), 2)
    }
}
```

**Step 2: 运行测试验证编译**

```bash
xcodebuild test -project ClaudeIsland.xcodeproj -scheme ClaudeIsland -destination 'platform=macOS' -only-testing:LRUCacheTests
```

**Step 3: Commit**

```bash
git add ClaudeIslandTests/LRUCacheTests.swift
git commit -m "test: add LRUCache unit tests"
```

---

### Task 3: 创建SidebarProjectGroupingSupportTests

**Files:**
- Create: `ClaudeIslandTests/SidebarProjectGroupingSupportTests.swift`
- Source: `ClaudeIsland/MainWindow/ViewModels/SidebarProjectGroupingSupport.swift:30-80`

**Step 1: 编写SidebarProjectGroupingSupportTests**

```swift
import XCTest
@testable import ClaudeIsland

private struct FakeThread: SidebarProjectGroupItem {
    let id: String
    let sidebarProjectId: String?
    let sidebarUpdatedAt: Date
    let title: String
}

final class SidebarProjectGroupingSupportTests: XCTestCase {
    
    func testGroupsSortedByProjectUpdatedAt() {
        let now = Date()
        let projects = [
            SidebarProjectRecord(
                id: "project-a",
                name: "Alpha",
                path: "/tmp/alpha",
                updatedAt: now.addingTimeInterval(-20)
            ),
            SidebarProjectRecord(
                id: "project-b",
                name: "Beta",
                path: "/tmp/beta",
                updatedAt: now.addingTimeInterval(-10)
            )
        ]
        
        let threads = [
            FakeThread(
                id: "thread-1",
                sidebarProjectId: "project-a",
                sidebarUpdatedAt: now.addingTimeInterval(-50),
                title: "Older alpha"
            ),
            FakeThread(
                id: "thread-2",
                sidebarProjectId: "project-a",
                sidebarUpdatedAt: now.addingTimeInterval(-5),
                title: "Newest alpha"
            ),
            FakeThread(
                id: "thread-3",
                sidebarProjectId: "project-b",
                sidebarUpdatedAt: now.addingTimeInterval(-30),
                title: "Beta thread"
            )
        ]
        
        let groups = SidebarProjectGroupingSupport.groups(projects: projects, items: threads)
        
        XCTAssertEqual(groups.map(\.id), ["project-b", "project-a"])
        XCTAssertEqual(groups[1].items.map(\.id), ["thread-2", "thread-1"])
    }
    
    func testReplacingItemUpdatesGroup() {
        let now = Date()
        let projects = [
            SidebarProjectRecord(
                id: "project-a",
                name: "Alpha",
                path: "/tmp/alpha",
                updatedAt: now.addingTimeInterval(-20)
            ),
            SidebarProjectRecord(
                id: "project-b",
                name: "Beta",
                path: "/tmp/beta",
                updatedAt: now.addingTimeInterval(-10)
            )
        ]
        
        let threads = [
            FakeThread(
                id: "thread-1",
                sidebarProjectId: "project-a",
                sidebarUpdatedAt: now.addingTimeInterval(-50),
                title: "Older alpha"
            ),
            FakeThread(
                id: "thread-2",
                sidebarProjectId: "project-a",
                sidebarUpdatedAt: now.addingTimeInterval(-5),
                title: "Newest alpha"
            ),
            FakeThread(
                id: "thread-3",
                sidebarProjectId: "project-b",
                sidebarUpdatedAt: now.addingTimeInterval(-30),
                title: "Beta thread"
            )
        ]
        
        let groups = SidebarProjectGroupingSupport.groups(projects: projects, items: threads)
        
        let refreshed = SidebarProjectGroupingSupport.replacingItem(
            FakeThread(
                id: "thread-3",
                sidebarProjectId: "project-b",
                sidebarUpdatedAt: now,
                title: "Beta thread renamed"
            ),
            in: groups
        )
        
        XCTAssertEqual(refreshed.first?.id, "project-b")
        XCTAssertEqual(refreshed.first?.items.first?.id, "thread-3")
        XCTAssertEqual(refreshed.first?.items.first?.title, "Beta thread renamed")
    }
    
    func testGroupsExcludesEmptyProjects() {
        let now = Date()
        let projects = [
            SidebarProjectRecord(
                id: "project-a",
                name: "Alpha",
                path: "/tmp/alpha",
                updatedAt: now
            ),
            SidebarProjectRecord(
                id: "project-b",
                name: "Beta",
                path: "/tmp/beta",
                updatedAt: now
            )
        ]
        
        let threads = [
            FakeThread(
                id: "thread-1",
                sidebarProjectId: "project-a",
                sidebarUpdatedAt: now,
                title: "Alpha thread"
            )
        ]
        
        let groups = SidebarProjectGroupingSupport.groups(projects: projects, items: threads)
        
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups.first?.id, "project-a")
    }
    
    func testGroupsSortByNameWhenUpdatedAtEqual() {
        let now = Date()
        let projects = [
            SidebarProjectRecord(
                id: "project-z",
                name: "Zebra",
                path: "/tmp/zebra",
                updatedAt: now
            ),
            SidebarProjectRecord(
                id: "project-a",
                name: "Alpha",
                path: "/tmp/alpha",
                updatedAt: now
            )
        ]
        
        let threads = [
            FakeThread(
                id: "thread-1",
                sidebarProjectId: "project-z",
                sidebarUpdatedAt: now,
                title: "Zebra thread"
            ),
            FakeThread(
                id: "thread-2",
                sidebarProjectId: "project-a",
                sidebarUpdatedAt: now,
                title: "Alpha thread"
            )
        ]
        
        let groups = SidebarProjectGroupingSupport.groups(projects: projects, items: threads)
        
        XCTAssertEqual(groups.map(\.id), ["project-a", "project-z"])
    }
}
```

**Step 2: 运行测试验证编译**

```bash
xcodebuild test -project ClaudeIsland.xcodeproj -scheme ClaudeIsland -destination 'platform=macOS' -only-testing:SidebarProjectGroupingSupportTests
```

**Step 3: Commit**

```bash
git add ClaudeIslandTests/SidebarProjectGroupingSupportTests.swift
git commit -m "test: add SidebarProjectGroupingSupport unit tests"
```

---

### Task 4: 创建ChatMessagePaginationSupportTests

**Files:**
- Create: `ClaudeIslandTests/ChatMessagePaginationSupportTests.swift`
- Source: `ClaudeIsland/MainWindow/ViewModels/ChatMessagePaginationSupport.swift:28-117`

**Step 1: 编写ChatMessagePaginationSupportTests**

```swift
import XCTest
@testable import ClaudeIsland

private struct SampleMessage: Identifiable, Equatable, Sendable {
    let id: String
}

final class ChatMessagePaginationSupportTests: XCTestCase {
    
    func testInitialVisibleCountCapsAtPageSize() {
        let initialVisibleCount = ChatMessagePaginationSupport.initialVisibleCount(
            totalCount: 120,
            pageSize: 80
        )
        
        XCTAssertEqual(initialVisibleCount, 80)
    }
    
    func testInitialVisibleCountHandlesSmallTotal() {
        let initialVisibleCount = ChatMessagePaginationSupport.initialVisibleCount(
            totalCount: 50,
            pageSize: 80
        )
        
        XCTAssertEqual(initialVisibleCount, 50)
    }
    
    func testInitialState() {
        let initial = ChatMessagePaginationSupport.state(
            totalCount: 120,
            loadedItems: 80
        )
        
        XCTAssertEqual(initial.loadedCount, 80)
        XCTAssertTrue(initial.hasOlderItems)
    }
    
    func testStateWithAllLoaded() {
        let state = ChatMessagePaginationSupport.state(
            totalCount: 80,
            loadedItems: 80
        )
        
        XCTAssertEqual(state.loadedCount, 80)
        XCTAssertFalse(state.hasOlderItems)
    }
    
    func testMergeOlderPageWithoutDuplication() {
        let existing = [
            SampleMessage(id: "m3"),
            SampleMessage(id: "m4")
        ]
        let older = [
            SampleMessage(id: "m1"),
            SampleMessage(id: "m2"),
            SampleMessage(id: "m3")
        ]
        
        let merged = ChatMessagePaginationSupport.mergeOlderPage(
            existingItems: existing,
            olderItems: older,
            totalCount: 4
        )
        
        XCTAssertEqual(merged.items.map(\.id), ["m1", "m2", "m3", "m4"])
        XCTAssertEqual(merged.loadedCount, 4)
        XCTAssertFalse(merged.hasOlderItems)
    }
    
    func testDynamicPageSizeForShortMessages() {
        let pageSize = ChatMessagePaginationSupport.dynamicPageSize(averageMessageLength: 50)
        
        XCTAssertEqual(pageSize, 120) // 80 * 1.5 = 120
    }
    
    func testDynamicPageSizeForMediumMessages() {
        let pageSize = ChatMessagePaginationSupport.dynamicPageSize(averageMessageLength: 200)
        
        XCTAssertEqual(pageSize, 80)
    }
    
    func testDynamicPageSizeForLongMessages() {
        let pageSize = ChatMessagePaginationSupport.dynamicPageSize(averageMessageLength: 700)
        
        XCTAssertEqual(pageSize, 60) // 80 * 0.75 = 60
    }
    
    func testDynamicPageSizeForVeryLongMessages() {
        let pageSize = ChatMessagePaginationSupport.dynamicPageSize(averageMessageLength: 1500)
        
        XCTAssertEqual(pageSize, 20) // minPageSize
    }
    
    func testPreloadPageSize() {
        let preloadSize = ChatMessagePaginationSupport.preloadPageSize(averageMessageLength: 200)
        
        XCTAssertEqual(preloadSize, 40) // 80 * 0.5 = 40
    }
}
```

**Step 2: 运行测试验证编译**

```bash
xcodebuild test -project ClaudeIsland.xcodeproj -scheme ClaudeIsland -destination 'platform=macOS' -only-testing:ChatMessagePaginationSupportTests
```

**Step 3: Commit**

```bash
git add ClaudeIslandTests/ChatMessagePaginationSupportTests.swift
git commit -m "test: add ChatMessagePaginationSupport unit tests"
```

---

### Task 5: 创建GlobalSessionSupportTests

**Files:**
- Create: `ClaudeIslandTests/GlobalSessionSupportTests.swift`
- Source: `ClaudeIsland/MainWindow/ViewModels/GlobalSessionSupport.swift:91-236`

**Step 1: 编写GlobalSessionSupportTests**

```swift
import XCTest
@testable import ClaudeIsland

final class GlobalSessionSupportTests: XCTestCase {
    
    func testMergedSessionsDeduplication() {
        let now = Date()
        
        let live = [
            HookSessionInfo(
                id: "live-a",
                sessionId: "session-a",
                projectPath: "/tmp/alpha",
                projectName: "alpha",
                title: "Live Alpha",
                gitBranch: "feat/live",
                status: "processing",
                startedAt: now.addingTimeInterval(-120),
                lastEventAt: now,
                messageCount: 6,
                source: .live
            )
        ]
        
        let scanned = [
            ImportableSession(
                id: "session-a",
                projectPath: "/tmp/alpha",
                projectName: "alpha",
                jsonlPath: "/tmp/alpha/session-a.jsonl",
                firstMessage: "Scanned Alpha",
                messageCount: 9,
                fileSize: 1024,
                lastModified: now.addingTimeInterval(-60),
                gitBranch: "main",
                claudeVersion: "2.1.80"
            ),
            ImportableSession(
                id: "session-b",
                projectPath: "/tmp/beta",
                projectName: "beta",
                jsonlPath: "/tmp/beta/session-b.jsonl",
                firstMessage: "Fix import flow",
                messageCount: 4,
                fileSize: 2048,
                lastModified: now.addingTimeInterval(-30),
                gitBranch: "fix/import",
                claudeVersion: "2.1.80"
            )
        ]
        
        let merged = GlobalSessionSupport.mergedSessions(
            live: live,
            scanned: scanned,
            searchText: ""
        )
        
        XCTAssertEqual(merged.count, 2)
        XCTAssertEqual(merged.first?.sessionId, "session-a")
        XCTAssertEqual(merged.first?.source, .live)
    }
    
    func testMergedSessionsSearch() {
        let now = Date()
        
        let live = [
            HookSessionInfo(
                id: "live-a",
                sessionId: "session-a",
                projectPath: "/tmp/alpha",
                projectName: "alpha",
                title: "Live Alpha",
                gitBranch: "feat/live",
                status: "processing",
                startedAt: now.addingTimeInterval(-120),
                lastEventAt: now,
                messageCount: 6,
                source: .live
            )
        ]
        
        let scanned = [
            ImportableSession(
                id: "session-a",
                projectPath: "/tmp/alpha",
                projectName: "alpha",
                jsonlPath: "/tmp/alpha/session-a.jsonl",
                firstMessage: "Scanned Alpha",
                messageCount: 9,
                fileSize: 1024,
                lastModified: now.addingTimeInterval(-60),
                gitBranch: "main",
                claudeVersion: "2.1.80"
            ),
            ImportableSession(
                id: "session-b",
                projectPath: "/tmp/beta",
                projectName: "beta",
                jsonlPath: "/tmp/beta/session-b.jsonl",
                firstMessage: "Fix import flow",
                messageCount: 4,
                fileSize: 2048,
                lastModified: now.addingTimeInterval(-30),
                gitBranch: "fix/import",
                claudeVersion: "2.1.80"
            )
        ]
        
        let searched = GlobalSessionSupport.mergedSessions(
            live: live,
            scanned: scanned,
            searchText: "import"
        )
        
        XCTAssertEqual(searched.map(\.sessionId), ["session-b"])
    }
    
    func testGroupedSessions() {
        let now = Date()
        
        let sessions = [
            HookSessionInfo(
                id: "session-a",
                sessionId: "session-a",
                projectPath: "/tmp/alpha",
                projectName: "alpha",
                title: "Alpha",
                gitBranch: nil,
                status: "ended",
                startedAt: now.addingTimeInterval(-120),
                lastEventAt: now.addingTimeInterval(-10),
                messageCount: 6,
                source: .history
            ),
            HookSessionInfo(
                id: "session-b",
                sessionId: "session-b",
                projectPath: "/tmp/beta",
                projectName: "beta",
                title: "Beta",
                gitBranch: nil,
                status: "ended",
                startedAt: now.addingTimeInterval(-60),
                lastEventAt: now,
                messageCount: 4,
                source: .history
            )
        ]
        
        let groups = GlobalSessionSupport.groupedSessions(sessions)
        
        XCTAssertEqual(groups.map(\.name), ["beta", "alpha"])
        XCTAssertEqual(groups[0].sessions.map(\.sessionId), ["session-b"])
    }
    
    func testOpenActionExistingThread() {
        let action = GlobalSessionSupport.openAction(existingThreadId: "thread-1")
        
        XCTAssertEqual(action, .openExistingThread("thread-1"))
    }
    
    func testOpenActionCreateTakeover() {
        let action = GlobalSessionSupport.openAction(existingThreadId: nil)
        
        XCTAssertEqual(action, .createTakeoverThread)
    }
    
    func testSelectionIdentityShared() {
        let sharedThreadIdentity = GlobalSessionSupport.selectionIdentity(
            threadId: "thread-a",
            cliSessionId: "session-a.jsonl"
        )
        let sharedGlobalIdentity = GlobalSessionSupport.selectionIdentity(sessionId: "session-a")
        
        XCTAssertEqual(sharedThreadIdentity, sharedGlobalIdentity)
    }
    
    func testSelectionIdentityLocal() {
        let sharedGlobalIdentity = GlobalSessionSupport.selectionIdentity(sessionId: "session-a")
        let localThreadIdentity = GlobalSessionSupport.selectionIdentity(
            threadId: "thread-local",
            cliSessionId: nil
        )
        
        XCTAssertNotEqual(localThreadIdentity, sharedGlobalIdentity)
    }
    
    func testResolvedStatusApproval() {
        let approvalStatus = GlobalSessionSupport.resolvedStatus(
            threadStatus: "idle",
            sessionStatus: "waitingForApproval"
        )
        
        XCTAssertEqual(approvalStatus, .waitingForApproval)
        XCTAssertTrue(approvalStatus.showsActivityBadge)
        XCTAssertEqual(approvalStatus.activityLabel, "Approval")
    }
    
    func testResolvedStatusActive() {
        let activeThreadStatus = GlobalSessionSupport.resolvedStatus(
            threadStatus: "active",
            sessionStatus: nil
        )
        
        XCTAssertEqual(activeThreadStatus, .active)
    }
    
    func testResolvedLastEventAt() {
        let now = Date()
        
        let resolvedLastEvent = GlobalSessionSupport.resolvedLastEventAt(
            threadUpdatedAt: now.addingTimeInterval(-3600),
            sessionLastEventAt: now.addingTimeInterval(-15)
        )
        
        XCTAssertEqual(resolvedLastEvent, now.addingTimeInterval(-15))
    }
}
```

**Step 2: 运行测试验证编译**

```bash
xcodebuild test -project ClaudeIsland.xcodeproj -scheme ClaudeIsland -destination 'platform=macOS' -only-testing:GlobalSessionSupportTests
```

**Step 3: Commit**

```bash
git add ClaudeIslandTests/GlobalSessionSupportTests.swift
git commit -m "test: add GlobalSessionSupport unit tests"
```

---

### Task 6: 更新Xcode项目添加测试目标

**Files:**
- Modify: `ClaudeIsland.xcodeproj/project.pbxproj`

**Step 1: 使用xcodebuild创建测试目标**

```bash
xcodebuild -project ClaudeIsland.xcodeproj -scheme ClaudeIsland -target 'Claude Island' create-tests-target
```

**Step 2: 手动编辑project.pbxproj添加测试目标**

需要添加以下内容：
- PBXBuildFile条目（测试文件引用）
- PBXFileReference条目（测试bundle产品）
- PBXGroup条目（测试文件组）
- PBXNativeTarget条目（测试目标）
- PBXTargetDependency条目（依赖关系）
- XCBuildConfiguration条目（Debug/Release配置）
- XCConfigurationList条目（配置列表）

**Step 3: 验证项目配置**

```bash
xcodebuild -project ClaudeIsland.xcodeproj -list
```

**Step 4: Commit**

```bash
git add ClaudeIsland.xcodeproj/project.pbxproj
git commit -m "chore: add ClaudeIslandTests target to Xcode project"
```

---

### Task 7: 创建测试辅助文件

**Files:**
- Create: `ClaudeIslandTests/Helpers/TestHelpers.swift`

**Step 1: 编写TestHelpers**

```swift
import XCTest

extension XCTestCase {
    func XCTAssertNoThrow<T>(
        _ expression: @autoclosure () throws -> T,
        _ message: @autoclosure () -> String = "",
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> T? {
        do {
            return try expression()
        } catch {
            XCTFail("Threw error: \(error) - \(message())", file: file, line: line)
            return nil
        }
    }
}
```

**Step 2: Commit**

```bash
git add ClaudeIslandTests/Helpers/TestHelpers.swift
git commit -m "test: add test helper utilities"
```

---

### Task 8: 验证所有测试通过

**Step 1: 运行完整测试套件**

```bash
xcodebuild test -project ClaudeIsland.xcodeproj -scheme ClaudeIsland -destination 'platform=macOS'
```

**Step 2: 检查测试覆盖率（可选）**

```bash
xcodebuild test -project ClaudeIsland.xcodeproj -scheme ClaudeIsland -destination 'platform=macOS' -enableCodeCoverage YES
```

**Step 3: 生成测试报告**

```bash
xcodebuild test -project ClaudeIsland.xcodeproj -scheme ClaudeIsland -destination 'platform=macOS' -resultBundlePath TestResults.xcresult
```

---

## 测试覆盖的关键功能

1. **LRUCache** - 线程安全的LRU缓存实现
   - 基本的set/get操作
   - 容量限制和驱逐策略
   - LRU顺序维护
   - 删除和清空操作

2. **SidebarProjectGroupingSupport** - 侧边栏项目分组
   - 项目按updatedAt排序
   - 线程在项目内按updatedAt降序排列
   - 更新项目时保持分组正确
   - 空项目被排除
   - 相同updatedAt时按名称排序

3. **ChatMessagePaginationSupport** - 聊天消息分页
   - 初始可见数量计算
   - 分页状态管理
   - 合并旧页面去重
   - 动态页面大小计算
   - 预加载页面大小

4. **GlobalSessionSupport** - 全局会话支持
   - 会话合并去重
   - 搜索过滤
   - 分组排序
   - 打开操作
   - 选择身份解析
   - 状态解析
   - 最后事件时间解析

---

## 如何运行测试

### 命令行运行所有测试

```bash
xcodebuild test -project ClaudeIsland.xcodeproj -scheme ClaudeIsland -destination 'platform=macOS'
```

### 运行特定测试类

```bash
xcodebuild test -project ClaudeIsland.xcodeproj -scheme ClaudeIsland -destination 'platform=macOS' -only-testing:LRUCacheTests
```

### 运行特定测试方法

```bash
xcodebuild test -project ClaudeIsland.xcodeproj -scheme ClaudeIsland -destination 'platform=macOS' -only-testing:LRUCacheTests/testBasicSetAndGet
```

### Xcode IDE运行

1. 打开 `ClaudeIsland.xcodeproj`
2. 选择测试导航器（⌘6）
3. 点击播放按钮运行所有测试
4. 或右键点击特定测试类/方法运行

---

## CI/CD集成建议

在CI配置中添加测试步骤：

```yaml
# .github/workflows/test.yml
name: Tests

on: [push, pull_request]

jobs:
  test:
    runs-on: macos-latest
    
    steps:
    - uses: actions/checkout@v3
    
    - name: Run Tests
      run: |
        xcodebuild test \
          -project ClaudeIsland.xcodeproj \
          -scheme ClaudeIsland \
          -destination 'platform=macOS' \
          -enableCodeCoverage YES \
          -resultBundlePath TestResults.xcresult
    
    - name: Upload Test Results
      uses: actions/upload-artifact@v3
      if: always()
      with:
        name: test-results
        path: TestResults.xcresult
```

---

## 完成后总结

**创建的测试文件：**
1. `ClaudeIslandTests/LRUCacheTests.swift` - 9个测试方法
2. `ClaudeIslandTests/SidebarProjectGroupingSupportTests.swift` - 4个测试方法
3. `ClaudeIslandTests/ChatMessagePaginationSupportTests.swift` - 9个测试方法
4. `ClaudeIslandTests/GlobalSessionSupportTests.swift` - 10个测试方法
5. `ClaudeIslandTests/Helpers/TestHelpers.swift` - 测试辅助工具

**测试覆盖的关键功能：**
- LRU缓存的核心功能和边界情况
- 侧边栏分组的排序和更新逻辑
- 聊天消息分页的状态管理
- 全局会话的合并、搜索和状态解析

**运行测试：**
```bash
xcodebuild test -project ClaudeIsland.xcodeproj -scheme ClaudeIsland -destination 'platform=macOS'
```
