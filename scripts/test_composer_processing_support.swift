import Foundation

func assertComposerProcessing(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        fputs("Assertion failed: \(message)\n", stderr)
        exit(1)
    }
}

@main
struct ComposerProcessingSupportTestRunner {
    static func main() {
        let thinking = ComposerProcessingSupport.descriptor(
            isProcessing: true,
            streamingText: "",
            thinkingText: ""
        )
        assertComposerProcessing(thinking?.title == "Claude is thinking", "processing without streamed content should read as thinking")
        assertComposerProcessing(
            thinking?.detail == "Reviewing context, checking tools, and preparing the next step.",
            "thinking detail should explain what Claude is doing"
        )

        let responding = ComposerProcessingSupport.descriptor(
            isProcessing: true,
            streamingText: "Partial answer",
            thinkingText: "Some reasoning"
        )
        assertComposerProcessing(responding?.title == "Claude is responding", "streamed content should switch status title to responding")
        assertComposerProcessing(
            responding?.detail == "Streaming the latest reply. You can interrupt or terminate at any time.",
            "responding detail should reflect the active stream"
        )

        let idle = ComposerProcessingSupport.descriptor(
            isProcessing: false,
            streamingText: "Partial answer",
            thinkingText: "Some reasoning"
        )
        assertComposerProcessing(idle == nil, "idle state should not produce a processing descriptor")

        print("composer processing support checks passed")
    }
}
