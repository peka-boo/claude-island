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
