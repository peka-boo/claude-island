import AppKit
import Foundation

func assertComposerAppearance(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        fputs("Assertion failed: \(message)\n", stderr)
        exit(1)
    }
}

@main
struct ComposerTextAppearanceTestRunner {
    static func main() {
        let font = NSFont.systemFont(ofSize: 16)
        let color = NSColor.white.withAlphaComponent(0.92)

        let normalized = ComposerTextAppearance.normalizedTextStorage(
            from: "hello",
            font: font,
            color: color
        )

        assertComposerAppearance(normalized.string == "hello", "should preserve the plain text content")
        assertComposerAppearance(
            (normalized.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor) == color,
            "should force the composer foreground color"
        )
        assertComposerAppearance(
            (normalized.attribute(.font, at: 0, effectiveRange: nil) as? NSFont) == font,
            "should force the composer font"
        )

        print("composer text appearance checks passed")
    }
}
