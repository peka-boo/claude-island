import Foundation

func assertSidebarGrouping(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        fputs("Assertion failed: \(message)\n", stderr)
        exit(1)
    }
}

private struct FakeThread: SidebarProjectGroupItem {
    let id: String
    let sidebarProjectId: String?
    let sidebarUpdatedAt: Date
    let title: String
}

@main
struct SidebarProjectGroupingSupportTestRunner {
    static func main() {
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
        assertSidebarGrouping(groups.map(\.id) == ["project-b", "project-a"], "project order should follow project updatedAt")
        assertSidebarGrouping(groups[1].items.map(\.id) == ["thread-2", "thread-1"], "threads inside a project should be sorted by updatedAt descending")

        let refreshed = SidebarProjectGroupingSupport.replacingItem(
            FakeThread(
                id: "thread-3",
                sidebarProjectId: "project-b",
                sidebarUpdatedAt: now,
                title: "Beta thread renamed"
            ),
            in: groups
        )
        assertSidebarGrouping(refreshed.first?.id == "project-b", "refreshing a thread should keep the hottest project at the top")
        assertSidebarGrouping(refreshed.first?.items.first?.id == "thread-3", "refreshed thread should stay in its project and sort to the top")
        assertSidebarGrouping(refreshed.first?.items.first?.title == "Beta thread renamed", "refreshing a thread should replace its visible data in place")

        print("sidebar project grouping support checks passed")
    }
}
