import Foundation

func assertHookMonitor(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        fputs("Assertion failed: \(message)\n", stderr)
        exit(1)
    }
}

@MainActor
final class FakeHookMonitorController: HookMonitorLifecycleControlling {
    private(set) var startCount = 0
    private(set) var stopCount = 0

    func startMonitoring() {
        startCount += 1
    }

    func stopMonitoring() {
        stopCount += 1
    }
}

@main
struct HookMonitorCoordinatorTestRunner {
    @MainActor
    static func main() {
        let enabledMonitor = FakeHookMonitorController()
        var persistedStates: [Bool] = []
        var actions: [String] = []

        HookMonitorCoordinator.setEnabled(
            true,
            persist: { persistedStates.append($0) },
            installHooks: { actions.append("install") },
            uninstallHooks: { actions.append("uninstall") },
            monitorController: enabledMonitor
        )

        assertHookMonitor(persistedStates == [true], "enabling should persist the enabled setting")
        assertHookMonitor(actions == ["install"], "enabling should install hooks")
        assertHookMonitor(enabledMonitor.startCount == 1, "enabling should start monitoring")
        assertHookMonitor(enabledMonitor.stopCount == 0, "enabling should not stop monitoring")

        let disabledMonitor = FakeHookMonitorController()
        persistedStates.removeAll()
        actions.removeAll()

        HookMonitorCoordinator.setEnabled(
            false,
            persist: { persistedStates.append($0) },
            installHooks: { actions.append("install") },
            uninstallHooks: { actions.append("uninstall") },
            monitorController: disabledMonitor
        )

        assertHookMonitor(persistedStates == [false], "disabling should persist the disabled setting")
        assertHookMonitor(actions == ["uninstall"], "disabling should uninstall hooks")
        assertHookMonitor(disabledMonitor.startCount == 0, "disabling should not start monitoring")
        assertHookMonitor(disabledMonitor.stopCount == 1, "disabling should stop monitoring")

        print("hook monitor coordinator checks passed")
    }
}
