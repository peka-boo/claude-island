import Foundation

func assertComposer(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        fputs("Assertion failed: \(message)\n", stderr)
        exit(1)
    }
}

@main
struct MessageComposerLogicTestRunner {
    static func main() {
        assertComposer(
            ComposerCommandLogic.slashQuery(in: "Please run /rev") == "rev",
            "should detect slash query at the end of the input"
        )

        let filtered = ComposerCommandLogic.filteredCommands(
            from: SessionCommandCatalog.builtIn,
            query: "ren"
        )
        assertComposer(
            filtered.contains(where: { $0.command == "/rename" }),
            "should filter built-in commands by label"
        )

        assertComposer(
            SessionCommandCatalog.builtIn.contains(where: { $0.command == "/doctor" }) == false,
            "unsupported faux Claude slash commands should not be advertised in the palette"
        )

        if case .local(.help)? = ComposerCommandLogic.submitAction(for: "/help") {
            // expected
        } else {
            fputs("Assertion failed: /help should resolve to local help action\n", stderr)
            exit(1)
        }

        if case .local(.clear)? = ComposerCommandLogic.submitAction(for: "/clear") {
            // expected
        } else {
            fputs("Assertion failed: /clear should resolve to local clear action\n", stderr)
            exit(1)
        }

        if case .local(.rename(let title))? = ComposerCommandLogic.submitAction(for: "claude rename Design Agent") {
            assertComposer(title == "Design Agent", "claude rename should extract the title")
        } else {
            fputs("Assertion failed: claude rename should resolve to local rename action\n", stderr)
            exit(1)
        }

        if case .send(let prompt)? = ComposerCommandLogic.submitAction(for: "/review login flow") {
            assertComposer(prompt == "/review login flow", "prompt slash commands should be sent to Claude")
        } else {
            fputs("Assertion failed: prompt slash command should remain sendable text\n", stderr)
            exit(1)
        }

        let helpCommand = SessionCommandCatalog.builtIn.first { $0.command == "/help" }
        assertComposer(
            ComposerCommandLogic.shouldSubmitPaletteSelection(
                text: "/help",
                selectedCommand: helpCommand
            ),
            "exact slash commands should submit instead of re-inserting themselves"
        )

        let renameCommand = SessionCommandCatalog.builtIn.first { $0.command == "/rename" }
        assertComposer(
            ComposerCommandLogic.shouldSubmitPaletteSelection(
                text: "/ren",
                selectedCommand: renameCommand
            ) == false,
            "partial slash queries should still insert the selected command"
        )

        print("message composer logic checks passed")
    }
}
