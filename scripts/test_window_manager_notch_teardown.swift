import AppKit
import Foundation

@inline(__always)
func assertWindowManager(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        fputs("Assertion failed: \(message)\n", stderr)
        exit(1)
    }
}

final class ScreenSelector {
    static let shared = ScreenSelector()
    var selectedScreen: NSScreen? = NSScreen.screens.first

    func refreshScreens() {}
}

final class TrackingWindow: NSWindow {
    var didClose = false

    override func close() {
        didClose = true
    }
}

final class NotchWindowController {
    let window: TrackingWindow?
    private(set) var showCount = 0

    init(screen: NSScreen) {
        self.window = TrackingWindow(
            contentRect: NSRect(x: 0, y: 0, width: 120, height: 48),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
    }

    func showWindow(_ sender: Any?) {
        showCount += 1
    }
}

@main
struct WindowManagerNotchTeardownTestRunner {
    static func main() {
        let manager = WindowManager()
        let controller = manager.setupNotchWindow()

        assertWindowManager(controller != nil, "setup should create a notch controller")
        assertWindowManager(controller?.showCount == 1, "setup should show the notch window once")
        assertWindowManager(controller?.window?.didClose == false, "window should start open")

        manager.tearDownNotchWindow()

        assertWindowManager(manager.windowController == nil, "teardown should clear the active controller")
        assertWindowManager(controller?.window?.didClose == true, "teardown should close the notch window")

        print("window manager notch teardown checks passed")
    }
}
