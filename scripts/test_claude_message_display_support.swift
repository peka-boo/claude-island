import CoreGraphics
import Foundation

@inline(__always)
func assertClaudeMessage(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        fputs("Assertion failed: \(message)\n", stderr)
        exit(1)
    }
}

@main
struct ClaudeMessageDisplaySupportTestRunner {
    static func main() {
        assertClaudeMessage(
            ClaudeMessageDisplaySupport.defaultHookDisplayMode == .popup,
            "popup should be the default claude hook display mode"
        )

        let notchSelection = ClaudeMessageDisplaySupport.settingsState(for: .notch)
        assertClaudeMessage(
            notchSelection.notchEnabled,
            "notch selection should keep the notch surface enabled"
        )
        assertClaudeMessage(
            !notchSelection.popupEnabled,
            "notch selection should disable the popup surface"
        )

        let popupSelection = ClaudeMessageDisplaySupport.settingsState(for: .popup)
        assertClaudeMessage(
            !popupSelection.notchEnabled,
            "popup selection should disable the notch surface"
        )
        assertClaudeMessage(
            popupSelection.popupEnabled,
            "popup selection should enable the popup surface"
        )

        let hiddenDesktopMode = ClaudeMessageDisplaySupport.desktopSurface(
            isEnabled: false,
            isCollapsed: false
        )
        assertClaudeMessage(
            hiddenDesktopMode == .hidden,
            "desktop surface should stay hidden when desktop floating is disabled"
        )

        let expandedDesktopMode = ClaudeMessageDisplaySupport.desktopSurface(
            isEnabled: true,
            isCollapsed: false
        )
        assertClaudeMessage(
            expandedDesktopMode == .expanded,
            "desktop surface should be expanded when enabled and not collapsed"
        )

        let collapsedDesktopMode = ClaudeMessageDisplaySupport.desktopSurface(
            isEnabled: true,
            isCollapsed: true
        )
        assertClaudeMessage(
            collapsedDesktopMode == .collapsed,
            "desktop surface should become collapsed when desktop floating is enabled and collapsed"
        )

        assertClaudeMessage(
            ClaudeMessageDisplaySupport.collapseActionTitle(
                isDesktopEnabled: false,
                isCollapsed: false
            ) == nil,
            "collapse action should be hidden when desktop floating is off"
        )
        assertClaudeMessage(
            ClaudeMessageDisplaySupport.collapseActionTitle(
                isDesktopEnabled: true,
                isCollapsed: false
            ) == "Collapse",
            "expanded desktop floating should show a collapse action"
        )
        assertClaudeMessage(
            ClaudeMessageDisplaySupport.collapseActionTitle(
                isDesktopEnabled: true,
                isCollapsed: true
            ) == "Expand",
            "collapsed desktop floating should show an expand action"
        )

        let expandedLayout = ClaudeMessageDisplaySupport.windowLayout(
            isDesktopEnabled: true,
            isCollapsed: false
        )
        assertClaudeMessage(
            expandedLayout.contentMode == .workspace,
            "expanded desktop floating should keep the full workspace visible"
        )
        assertClaudeMessage(
            expandedLayout.size.width > 700 && expandedLayout.size.height > 500,
            "expanded desktop floating should keep a large window footprint"
        )

        let collapsedLayout = ClaudeMessageDisplaySupport.windowLayout(
            isDesktopEnabled: true,
            isCollapsed: true
        )
        assertClaudeMessage(
            collapsedLayout.contentMode == .compactPanel,
            "collapsed desktop floating should switch to the compact panel content"
        )
        assertClaudeMessage(
            collapsedLayout.size.width < expandedLayout.size.width &&
                collapsedLayout.size.height < expandedLayout.size.height,
            "collapsed desktop floating should shrink the window"
        )

        assertClaudeMessage(
            ClaudeMessageDisplaySupport.menuTitle(for: .notch) == "Current Notch",
            "notch mode should expose the current notch title"
        )
        assertClaudeMessage(
            ClaudeMessageDisplaySupport.menuTitle(for: .popup) == "Popup",
            "popup mode should expose the popup title"
        )

        print("claude message display support checks passed")
    }
}
