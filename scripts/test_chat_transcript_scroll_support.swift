import Foundation

func assertTranscriptScroll(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        fputs("Assertion failed: \(message)\n", stderr)
        exit(1)
    }
}

private struct SampleTranscriptItem: Identifiable, Equatable, Sendable {
    let id: String
}

@main
struct ChatTranscriptScrollSupportTestRunner {
    static func main() {
        let oldItems = [
            SampleTranscriptItem(id: "m1"),
            SampleTranscriptItem(id: "m2")
        ]
        let newItems = [
            SampleTranscriptItem(id: "m3"),
            SampleTranscriptItem(id: "m4")
        ]

        let initialJump = ChatTranscriptScrollSupport.scrollAction(
            oldItems: oldItems,
            newItems: newItems,
            hasAppliedInitialPosition: false
        )
        assertTranscriptScroll(initialJump == .jumpToLatest, "thread switches should jump to latest without animating")

        let streamingAppend = ChatTranscriptScrollSupport.scrollAction(
            oldItems: oldItems,
            newItems: oldItems + [SampleTranscriptItem(id: "m5")],
            hasAppliedInitialPosition: true
        )
        assertTranscriptScroll(streamingAppend == .animateToLatest, "new replies should animate to latest")

        let olderPageLoad = ChatTranscriptScrollSupport.scrollAction(
            oldItems: oldItems,
            newItems: [SampleTranscriptItem(id: "m0")] + oldItems,
            hasAppliedInitialPosition: true
        )
        assertTranscriptScroll(olderPageLoad == .none, "loading older items should preserve the current viewport")

        let sourceSwap = ChatTranscriptScrollSupport.scrollAction(
            oldItems: [],
            newItems: newItems,
            hasAppliedInitialPosition: true
        )
        assertTranscriptScroll(sourceSwap == .jumpToLatest, "swapping to structured history should still pin to latest once")

        assertTranscriptScroll(
            ChatTranscriptScrollSupport.bottomScrollTarget(hasVisibleContent: false) == nil,
            "empty transcripts should not request a bottom anchor scroll target"
        )
        assertTranscriptScroll(
            ChatTranscriptScrollSupport.bottomScrollTarget(hasVisibleContent: true) == ChatTranscriptScrollSupport.bottomAnchorID,
            "visible transcripts should scroll to the dedicated bottom anchor instead of the last content item"
        )

        print("chat transcript scroll checks passed")
    }
}
