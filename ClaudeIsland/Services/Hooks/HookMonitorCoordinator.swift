//
//  HookMonitorCoordinator.swift
//  ClaudeIsland
//
//  Shared coordinator for hook-monitor enablement so UI entry points and
//  launch observers all trigger the same side effects.
//

import Foundation

@MainActor
protocol HookMonitorLifecycleControlling: AnyObject {
    func startMonitoring()
    func stopMonitoring()
}

@MainActor
enum HookMonitorCoordinator {
    static func setEnabled(
        _ enabled: Bool,
        persist: @MainActor (Bool) -> Void,
        installHooks: @MainActor () -> Void,
        uninstallHooks: @MainActor () -> Void,
        monitorController: HookMonitorLifecycleControlling
    ) {
        persist(enabled)
        apply(
            enabled: enabled,
            installHooks: installHooks,
            uninstallHooks: uninstallHooks,
            monitorController: monitorController
        )
    }

    static func apply(
        enabled: Bool,
        installHooks: @MainActor () -> Void,
        uninstallHooks: @MainActor () -> Void,
        monitorController: HookMonitorLifecycleControlling
    ) {
        if enabled {
            installHooks()
            monitorController.startMonitoring()
        } else {
            uninstallHooks()
            monitorController.stopMonitoring()
        }
    }
}
