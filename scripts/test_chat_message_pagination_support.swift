import Foundation

func assertPaging(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        fputs("Assertion failed: \(message)\n", stderr)
        exit(1)
    }
}

private struct SampleMessage: Identifiable, Equatable, Sendable {
    let id: String
}

@main
struct ChatMessagePaginationSupportTestRunner {
    static func main() {
        let initialVisibleCount = ChatMessagePaginationSupport.initialVisibleCount(
            totalCount: 120,
            pageSize: 80
        )
        assertPaging(initialVisibleCount == 80, "initial visible count should cap at page size")

        let initial = ChatMessagePaginationSupport.state(
            totalCount: 120,
            loadedItems: 80
        )
        assertPaging(initial.loadedCount == 80, "initial state should preserve loaded message count")
        assertPaging(initial.hasOlderItems, "initial state should expose older items when total count exceeds loaded count")

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
        assertPaging(merged.items.map(\.id) == ["m1", "m2", "m3", "m4"], "older page should prepend without duplicating overlap")
        assertPaging(merged.loadedCount == 4, "merged count should equal unique visible messages")
        assertPaging(merged.hasOlderItems == false, "merged state should stop when all messages are now loaded")

        print("chat message pagination checks passed")
    }
}
