import Foundation

func assertImportFilter(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        fputs("Assertion failed: \(message)\n", stderr)
        exit(1)
    }
}

@main
struct ImportSessionFilterSupportTestRunner {
    static func main() {
        let now = Date()
        let sessions = [
            ImportableSession(
                id: "session-a",
                projectPath: "/tmp/project-a",
                projectName: "project-a",
                jsonlPath: "/tmp/project-a/session-a.jsonl",
                firstMessage: "Fix login bug",
                messageCount: 12,
                fileSize: 1024,
                lastModified: now,
                gitBranch: "main",
                claudeVersion: "2.1.80"
            ),
            ImportableSession(
                id: "session-b",
                projectPath: "/tmp/project-b",
                projectName: "project-b",
                jsonlPath: "/tmp/project-b/session-b.jsonl",
                firstMessage: "Refactor import flow",
                messageCount: 8,
                fileSize: 2048,
                lastModified: now.addingTimeInterval(-60),
                gitBranch: "feat/import-filter",
                claudeVersion: "2.1.80"
            ),
            ImportableSession(
                id: "session-c",
                projectPath: "/tmp/project-a",
                projectName: "project-a",
                jsonlPath: "/tmp/project-a/session-c.jsonl",
                firstMessage: "Design new sidebar",
                messageCount: 20,
                fileSize: 4096,
                lastModified: now.addingTimeInterval(-120),
                gitBranch: "design-pass",
                claudeVersion: "2.1.80"
            )
        ]

        let filters = ImportSessionFilterSupport.projectFilters(from: sessions)
        assertImportFilter(filters.map(\.title) == ["All", "project-a", "project-b"], "project filters should include All and unique sorted project names")
        assertImportFilter(filters.first?.count == 3, "All filter should show total session count")
        assertImportFilter(filters[1].count == 2, "project-specific filter should include project session count")

        let allSessions = ImportSessionFilterSupport.filteredSessions(
            sessions,
            searchText: "",
            selectedProject: nil
        )
        assertImportFilter(allSessions.count == 3, "empty search and no project selection should keep all sessions")

        let projectASessions = ImportSessionFilterSupport.filteredSessions(
            sessions,
            searchText: "",
            selectedProject: "project-a"
        )
        assertImportFilter(projectASessions.map(\.id) == ["session-a", "session-c"], "project filter should keep only matching project sessions")

        let searchedSessions = ImportSessionFilterSupport.filteredSessions(
            sessions,
            searchText: "import",
            selectedProject: nil
        )
        assertImportFilter(searchedSessions.map(\.id) == ["session-b"], "search should still match first message and branch text")

        let combinedFilter = ImportSessionFilterSupport.filteredSessions(
            sessions,
            searchText: "design",
            selectedProject: "project-a"
        )
        assertImportFilter(combinedFilter.map(\.id) == ["session-c"], "search and project filter should combine")

        print("import session filter checks passed")
    }
}
