//
//  ComposerTextView.swift
//  ClaudeIsland
//
//  AppKit-backed multiline composer with Enter-to-send behavior.
//

import AppKit
import SwiftUI

enum ComposerTextAppearance {
    static func typingAttributes(font: NSFont, color: NSColor) -> [NSAttributedString.Key: Any] {
        [
            .font: font,
            .foregroundColor: color,
        ]
    }

    static func normalizedTextStorage(from string: String, font: NSFont, color: NSColor) -> NSAttributedString {
        NSAttributedString(
            string: string,
            attributes: typingAttributes(font: font, color: color)
        )
    }

    static func plainText(from pasteboard: NSPasteboard) -> String? {
        pasteboard.string(forType: .string)
    }
}

struct ComposerTextView: NSViewRepresentable {
    @Binding var text: String

    let isEditable: Bool
    let isCommandPaletteVisible: Bool
    let onSubmit: () -> Void
    let onMoveCommandSelection: (Int) -> Void
    let onConfirmCommandSelection: () -> Void
    let onDismissCommandSelection: () -> Void
    let onHeightChange: (CGFloat) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            text: $text,
            onSubmit: onSubmit,
            onMoveCommandSelection: onMoveCommandSelection,
            onConfirmCommandSelection: onConfirmCommandSelection,
            onDismissCommandSelection: onDismissCommandSelection,
            onHeightChange: onHeightChange
        )
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true

        let textView = CommandAwareTextView()
        textView.delegate = context.coordinator
        textView.isEditable = isEditable
        textView.isSelectable = true
        textView.isRichText = false
        textView.importsGraphics = false
        textView.drawsBackground = false
        textView.composerTextColor = NSColor.white.withAlphaComponent(0.92)
        textView.composerFont = .systemFont(ofSize: MainWindowTheme.scaled(16))
        textView.textContainerInset = NSSize(width: 0, height: MainWindowTheme.scaled(9))
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.minSize = NSSize(width: 0, height: MainWindowTheme.scaled(42))
        textView.string = text
        textView.applyComposerAppearance()

        textView.onSubmit = onSubmit
        textView.onMoveCommandSelection = onMoveCommandSelection
        textView.onConfirmCommandSelection = onConfirmCommandSelection
        textView.onDismissCommandSelection = onDismissCommandSelection
        textView.isCommandPaletteVisible = isCommandPaletteVisible

        scrollView.documentView = textView

        DispatchQueue.main.async {
            scrollView.window?.makeFirstResponder(textView)
            context.coordinator.recalculateHeight(for: textView)
        }

        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? CommandAwareTextView else { return }

        if textView.string != text {
            textView.string = text
            textView.applyComposerAppearance()
        }

        textView.isEditable = isEditable
        textView.applyComposerAppearance()
        textView.onSubmit = onSubmit
        textView.onMoveCommandSelection = onMoveCommandSelection
        textView.onConfirmCommandSelection = onConfirmCommandSelection
        textView.onDismissCommandSelection = onDismissCommandSelection
        textView.isCommandPaletteVisible = isCommandPaletteVisible

        DispatchQueue.main.async {
            context.coordinator.recalculateHeight(for: textView)
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        @Binding private var text: String

        private let onSubmit: () -> Void
        private let onMoveCommandSelection: (Int) -> Void
        private let onConfirmCommandSelection: () -> Void
        private let onDismissCommandSelection: () -> Void
        private let onHeightChange: (CGFloat) -> Void

        init(
            text: Binding<String>,
            onSubmit: @escaping () -> Void,
            onMoveCommandSelection: @escaping (Int) -> Void,
            onConfirmCommandSelection: @escaping () -> Void,
            onDismissCommandSelection: @escaping () -> Void,
            onHeightChange: @escaping (CGFloat) -> Void
        ) {
            self._text = text
            self.onSubmit = onSubmit
            self.onMoveCommandSelection = onMoveCommandSelection
            self.onConfirmCommandSelection = onConfirmCommandSelection
            self.onDismissCommandSelection = onDismissCommandSelection
            self.onHeightChange = onHeightChange
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text = textView.string
            recalculateHeight(for: textView)
        }

        func recalculateHeight(for textView: NSTextView) {
            guard let layoutManager = textView.layoutManager,
                  let textContainer = textView.textContainer else { return }

            layoutManager.ensureLayout(for: textContainer)
            let usedRect = layoutManager.usedRect(for: textContainer)
            let verticalInset = textView.textContainerInset.height * 2
            let measuredHeight = ceil(usedRect.height + verticalInset)
            onHeightChange(measuredHeight)
        }
    }
}

private final class CommandAwareTextView: NSTextView {
    var onSubmit: (() -> Void)?
    var onMoveCommandSelection: ((Int) -> Void)?
    var onConfirmCommandSelection: (() -> Void)?
    var onDismissCommandSelection: (() -> Void)?
    var isCommandPaletteVisible = false
    var composerFont: NSFont = .systemFont(ofSize: MainWindowTheme.scaled(16))
    var composerTextColor: NSColor = .white

    func applyComposerAppearance() {
        font = composerFont
        textColor = composerTextColor
        insertionPointColor = .white
        typingAttributes = ComposerTextAppearance.typingAttributes(
            font: composerFont,
            color: composerTextColor
        )
        normalizeTextStorageAppearance()
    }

    override func paste(_ sender: Any?) {
        guard isEditable else { return }

        if let plainText = ComposerTextAppearance.plainText(from: .general) {
            insertText(plainText, replacementRange: selectedRange())
            return
        }

        super.paste(sender)
        normalizeTextStorageAppearance()
    }

    override func insertText(_ insertString: Any, replacementRange: NSRange) {
        let plainString: String
        if let attributed = insertString as? NSAttributedString {
            plainString = attributed.string
        } else if let string = insertString as? String {
            plainString = string
        } else {
            super.insertText(insertString, replacementRange: replacementRange)
            normalizeTextStorageAppearance()
            return
        }

        super.insertText(plainString, replacementRange: replacementRange)
        normalizeTextStorageAppearance()
    }

    override func doCommand(by selector: Selector) {
        switch selector {
        case #selector(insertNewline(_:)):
            if isCommandPaletteVisible {
                onConfirmCommandSelection?()
                return
            }

            if NSApp.currentEvent?.modifierFlags.contains(.shift) == true {
                super.doCommand(by: selector)
                return
            }

            onSubmit?()

        case #selector(moveUp(_:)):
            if isCommandPaletteVisible {
                onMoveCommandSelection?(-1)
                return
            }
            super.doCommand(by: selector)

        case #selector(moveDown(_:)):
            if isCommandPaletteVisible {
                onMoveCommandSelection?(1)
                return
            }
            super.doCommand(by: selector)

        case #selector(cancelOperation(_:)):
            if isCommandPaletteVisible {
                onDismissCommandSelection?()
                return
            }
            super.doCommand(by: selector)

        default:
            super.doCommand(by: selector)
        }
    }

    private func normalizeTextStorageAppearance() {
        guard let textStorage else { return }

        let selection = selectedRange()
        textStorage.setAttributedString(
            ComposerTextAppearance.normalizedTextStorage(
                from: textStorage.string,
                font: composerFont,
                color: composerTextColor
            )
        )

        let safeLocation = min(selection.location, textStorage.length)
        let safeLength = min(selection.length, max(0, textStorage.length - safeLocation))
        setSelectedRange(NSRange(location: safeLocation, length: safeLength))
    }
}
