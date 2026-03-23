import Foundation

func assertToolResultPresentation(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        fputs("Assertion failed: \(message)\n", stderr)
        exit(1)
    }
}

@main
struct ChatToolResultPresentationTestRunner {
    static func main() {
        let shortResult = "ok\ncompleted"
        let shortPresentation = ChatToolResultPresentationSupport.presentation(for: shortResult)
        assertToolResultPresentation(
            shortPresentation.shouldCollapse == false,
            "short tool results should stay expanded inline"
        )
        assertToolResultPresentation(
            shortPresentation.previewText == shortResult,
            "short tool results should preserve their full preview text"
        )

        let longLines = (1...18).map { "let line\($0) = \($0)" }.joined(separator: "\n")
        let longPresentation = ChatToolResultPresentationSupport.presentation(for: longLines)
        assertToolResultPresentation(
            longPresentation.shouldCollapse,
            "multi-line file-like outputs should default to collapsed mode"
        )
        assertToolResultPresentation(
            longPresentation.collapseTitle == "File Content",
            "code-like outputs should be labeled as file content in the collapsed header"
        )
        assertToolResultPresentation(
            longPresentation.previewLineCount == ChatToolResultPresentationSupport.previewLineLimit,
            "collapsed previews should cap themselves to the configured preview line limit"
        )
        assertToolResultPresentation(
            longPresentation.hiddenLineCount == 18 - ChatToolResultPresentationSupport.previewLineLimit,
            "collapsed previews should report how many lines remain hidden"
        )
        assertToolResultPresentation(
            longPresentation.previewText.contains("let line1 = 1") && longPresentation.previewText.contains("let line8 = 8"),
            "collapsed previews should keep the leading file lines visible"
        )
        assertToolResultPresentation(
            longPresentation.previewText.contains("let line9 = 9") == false,
            "collapsed previews should not spill past the preview line limit"
        )

        let singleLongLine = String(repeating: "abcdef", count: 220)
        let singleLinePresentation = ChatToolResultPresentationSupport.presentation(for: singleLongLine)
        assertToolResultPresentation(
            singleLinePresentation.shouldCollapse,
            "very long single-line outputs should also collapse"
        )
        assertToolResultPresentation(
            singleLinePresentation.collapseTitle == "Large Output",
            "generic long outputs should keep the broader collapse title"
        )
        assertToolResultPresentation(
            singleLinePresentation.previewText.count <= ChatToolResultPresentationSupport.previewCharacterLimit + 1,
            "single-line previews should be character-clamped instead of rendering the full payload"
        )

        print("chat tool result presentation checks passed")
    }
}
