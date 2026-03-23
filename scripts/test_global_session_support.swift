import Foundation

func assertGlobalSession(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        fputs("Assertion failed: \(message)\n", stderr)
        exit(1)
    }
}

@main
struct GlobalSessionSupportTestRunner {
    static func main() {
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
        assertGlobalSession(merged.count == 2, "merged sessions should deduplicate live and scanned copies")
        assertGlobalSession(merged.first?.sessionId == "session-a", "live session should win dedupe and stay first when newest")
        assertGlobalSession(merged.first?.source == .live, "live copy should override scanned history for the same session id")

        let searched = GlobalSessionSupport.mergedSessions(
            live: live,
            scanned: scanned,
            searchText: "import"
        )
        assertGlobalSession(searched.map(\.sessionId) == ["session-b"], "search should match historical session title and branch text")

        let groups = GlobalSessionSupport.groupedSessions(merged)
        assertGlobalSession(groups.map(\.name) == ["alpha", "beta"], "grouped sessions should preserve project grouping order by newest activity")
        assertGlobalSession(groups[0].sessions.map(\.sessionId) == ["session-a"], "first group should contain alpha sessions")

        let reuseAction = GlobalSessionSupport.openAction(existingThreadId: "thread-1")
        assertGlobalSession(reuseAction == .openExistingThread("thread-1"), "existing threads should be reused from global monitor")

        let createAction = GlobalSessionSupport.openAction(existingThreadId: nil)
        assertGlobalSession(createAction == .createTakeoverThread, "missing threads should create a takeover thread")

        let sharedThreadIdentity = GlobalSessionSupport.selectionIdentity(
            threadId: "thread-a",
            cliSessionId: "session-a.jsonl"
        )
        let sharedGlobalIdentity = GlobalSessionSupport.selectionIdentity(sessionId: "session-a")
        assertGlobalSession(
            sharedThreadIdentity == sharedGlobalIdentity,
            "thread-backed sessions should share the same canonical selection identity as global monitor entries"
        )

        let localThreadIdentity = GlobalSessionSupport.selectionIdentity(
            threadId: "thread-local",
            cliSessionId: nil
        )
        assertGlobalSession(
            localThreadIdentity != sharedGlobalIdentity,
            "local-only threads should keep a thread-scoped selection identity"
        )

        let approvalStatus = GlobalSessionSupport.resolvedStatus(
            threadStatus: "idle",
            sessionStatus: "waitingForApproval"
        )
        assertGlobalSession(
            approvalStatus == .waitingForApproval,
            "live monitor status should override persisted thread status for shared sessions"
        )
        assertGlobalSession(
            approvalStatus.showsActivityBadge,
            "approval states should opt into the shared activity badge treatment"
        )
        assertGlobalSession(
            approvalStatus.activityLabel == "Approval",
            "shared activity badge text should come from the canonical status enum"
        )

        let activeThreadStatus = GlobalSessionSupport.resolvedStatus(
            threadStatus: "active",
            sessionStatus: nil
        )
        assertGlobalSession(
            activeThreadStatus == .active,
            "standalone threads should still surface their local thread status when no global session exists"
        )

        let resolvedLastEvent = GlobalSessionSupport.resolvedLastEventAt(
            threadUpdatedAt: now.addingTimeInterval(-3600),
            sessionLastEventAt: now.addingTimeInterval(-15)
        )
        assertGlobalSession(
            resolvedLastEvent == now.addingTimeInterval(-15),
            "shared sessions should reuse the global monitor activity timestamp when available"
        )

        print("global session support checks passed")
    }
}
