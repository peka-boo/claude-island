import Foundation

func assertStreamingResponse(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        fputs("Assertion failed: \(message)\n", stderr)
        exit(1)
    }
}

@main
struct StreamingResponseSupportTestRunner {
    static func main() {
        var buffer = StreamingResponseBuffer()

        assertStreamingResponse(
            buffer.committedText.isEmpty,
            "new streaming buffers should start empty"
        )
        assertStreamingResponse(
            buffer.pendingText.isEmpty,
            "new streaming buffers should not have pending text"
        )

        buffer.append("Hello")
        assertStreamingResponse(
            buffer.committedText.isEmpty,
            "incoming chunks should stay pending until the scheduled UI flush"
        )
        assertStreamingResponse(
            buffer.pendingText == "Hello",
            "pending text should accumulate streamed chunks"
        )
        assertStreamingResponse(
            buffer.flush(),
            "flushing pending content should report that it published an update"
        )
        assertStreamingResponse(
            buffer.committedText == "Hello",
            "flushing should move pending content into the committed text"
        )
        assertStreamingResponse(
            buffer.pendingText.isEmpty,
            "flushing should clear the pending buffer"
        )

        buffer.append(" world")
        assertStreamingResponse(
            buffer.resolvedText(fallback: "") == "Hello world",
            "final message resolution should include still-pending chunks"
        )
        assertStreamingResponse(
            buffer.flush(),
            "a second flush should publish the newly pending chunk"
        )
        assertStreamingResponse(
            buffer.committedText == "Hello world",
            "committed text should keep the full streamed reply after multiple flushes"
        )
        assertStreamingResponse(
            buffer.flush() == false,
            "flushing without new chunks should be a no-op"
        )

        buffer.reset()
        assertStreamingResponse(
            buffer.resolvedText(fallback: "Fallback") == "Fallback",
            "empty buffers should fall back to the CLI result payload"
        )

        assertStreamingResponse(
            StreamingResponseRenderingSupport.mode(isStreaming: true) == .plainText,
            "live streaming should use plain text rendering to avoid repeated markdown parsing"
        )
        assertStreamingResponse(
            StreamingResponseRenderingSupport.mode(isStreaming: false) == .markdown,
            "settled messages should keep markdown rendering"
        )

        print("streaming response support checks passed")
    }
}
