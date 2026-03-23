import Foundation
import SwiftData

func assertImportTracking(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        fputs("Assertion failed: \(message)\n", stderr)
        exit(1)
    }
}

@main
struct ImportTrackingTestRunner {
    static func main() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("claude-island-import-tracking-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let schema = Schema([
            Project.self,
            Thread.self,
            Message.self,
            ImportRecord.self,
        ])
        let config = ModelConfiguration(
            "ImportTrackingTest",
            schema: schema,
            url: tempDir.appendingPathComponent("import-tracking.store"),
            allowsSave: true
        )
        let container = try ModelContainer(for: schema, configurations: [config])
        let actor = BackgroundDataActor(modelContainer: container)

        let projectId = try await actor.findOrCreateProject(path: "/tmp/import-tracking-demo")
        let threadId = try await actor.createThread(
            projectId: projectId,
            title: "Imported Session",
            source: .imported,
            cliSessionId: "session-1"
        )
        try await actor.recordImport(cliSessionId: "session-1", threadId: threadId)

        let firstImported = try await actor.isImported(cliSessionId: "session-1")
        assertImportTracking(
            firstImported,
            "freshly imported session should be marked as imported"
        )

        try await actor.deleteThread(threadId: threadId)

        let firstReimportable = try await actor.isImported(cliSessionId: "session-1")
        assertImportTracking(
            !firstReimportable,
            "deleting the imported thread should make the session importable again"
        )

        let projectId2 = try await actor.findOrCreateProject(path: "/tmp/import-tracking-demo-2")
        let threadId2 = try await actor.createThread(
            projectId: projectId2,
            title: "Imported Session 2",
            source: .imported,
            cliSessionId: "session-2"
        )
        try await actor.recordImport(cliSessionId: "session-2", threadId: threadId2)

        let secondImported = try await actor.isImported(cliSessionId: "session-2")
        assertImportTracking(
            secondImported,
            "second imported session should be marked as imported"
        )

        try await actor.deleteProject(projectId: projectId2)

        let secondReimportable = try await actor.isImported(cliSessionId: "session-2")
        assertImportTracking(
            !secondReimportable,
            "deleting a project should also clear linked import records"
        )

        print("import tracking checks passed")
    }
}
