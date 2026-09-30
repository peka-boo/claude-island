import AppKit
import IOKit
import Mixpanel
import Sparkle
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    private var windowManager: WindowManager?
    private var screenObserver: ScreenObserver?
    private var updateCheckTimer: Timer?

    static var shared: AppDelegate?
    let updater: SPUUpdater
    private let userDriver: NotchUserDriver

    var windowController: NotchWindowController? {
        windowManager?.windowController
    }

    override init() {
        userDriver = NotchUserDriver()
        updater = SPUUpdater(
            hostBundle: Bundle.main,
            applicationBundle: Bundle.main,
            userDriver: userDriver,
            delegate: nil
        )
        super.init()
        AppDelegate.shared = self

        do {
            try updater.start()
        } catch {
            print("Failed to start Sparkle updater: \(error)")
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if !ensureSingleInstance() {
            NSApplication.shared.terminate(nil)
            return
        }

        Mixpanel.initialize(token: "49814c1436104ed108f3fc4735228496")

        let distinctId = getOrCreateDistinctId()
        Mixpanel.mainInstance().identify(distinctId: distinctId)

        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown"
        let osVersion = Foundation.ProcessInfo.processInfo.operatingSystemVersionString

        Mixpanel.mainInstance().registerSuperProperties([
            "app_version": version,
            "build_number": build,
            "macos_version": osVersion
        ])

        fetchAndRegisterClaudeVersion()

        Mixpanel.mainInstance().people.set(properties: [
            "app_version": version,
            "build_number": build,
            "macos_version": osVersion
        ])

        Mixpanel.mainInstance().track(event: "App Launched")
        Mixpanel.mainInstance().flush()

        // Show in Dock (main window app)
        NSApplication.shared.setActivationPolicy(.regular)

        Task { @MainActor in
            HookMonitorCoordinator.apply(
                enabled: AppSettings.hookMonitorEnabled,
                installHooks: HookInstaller.installIfNeeded,
                uninstallHooks: HookInstaller.uninstall,
                monitorController: ClaudeSessionMonitor.shared
            )
        }

        _ = ClaudeHookPopupManager.shared

        // Notch — only create if enabled in settings
        if AppSettings.notchEnabled {
            windowManager = WindowManager()
            _ = windowManager?.setupNotchWindow()
        }

        screenObserver = ScreenObserver { [weak self] in
            self?.handleScreenChange()
        }

        // Toggle observers
        setupToggleObservers()

        if updater.canCheckForUpdates {
            updater.checkForUpdates()
        }

        updateCheckTimer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
            guard let updater = self?.updater, updater.canCheckForUpdates else { return }
            updater.checkForUpdates()
        }
    }

    private func handleScreenChange() {
        _ = windowManager?.setupNotchWindow()
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Clean up all CLI subprocesses
        Task {
            await ClaudeIslandApp.cliManager.terminateAll()
        }

        Task { @MainActor in
            ClaudeSessionMonitor.shared.stopMonitoring()
        }
        Mixpanel.mainInstance().flush()
        updateCheckTimer?.invalidate()
        screenObserver = nil
    }

    // MARK: - Toggle Observers

    private func setupToggleObservers() {
        NotificationCenter.default.addObserver(
            forName: .notchToggled,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let enabled = notification.userInfo?["enabled"] as? Bool ?? false
            if enabled {
                if self?.windowManager == nil {
                    self?.windowManager = WindowManager()
                }
                _ = self?.windowManager?.setupNotchWindow()
            } else {
                self?.windowManager?.tearDownNotchWindow()
                self?.windowManager = nil
            }
        }

        NotificationCenter.default.addObserver(
            forName: .hookMonitorToggled,
            object: nil,
            queue: .main
        ) { notification in
            let enabled = notification.userInfo?["enabled"] as? Bool ?? false
            Task { @MainActor in
                HookMonitorCoordinator.apply(
                    enabled: enabled,
                    installHooks: HookInstaller.installIfNeeded,
                    uninstallHooks: HookInstaller.uninstall,
                    monitorController: ClaudeSessionMonitor.shared
                )
            }
        }
    }

    private func getOrCreateDistinctId() -> String {
        let key = "mixpanel_distinct_id"

        if let existingId = UserDefaults.standard.string(forKey: key) {
            return existingId
        }

        let platformExpert = IOServiceGetMatchingService(
            kIOMainPortDefault,
            IOServiceMatching("IOPlatformExpertDevice")
        )
        defer { IOObjectRelease(platformExpert) }

        if let uuid = IORegistryEntryCreateCFProperty(
            platformExpert,
            kIOPlatformUUIDKey as CFString,
            kCFAllocatorDefault,
            0
        )?.takeRetainedValue() as? String {
            UserDefaults.standard.set(uuid, forKey: key)
            return uuid
        }

        let newId = UUID().uuidString
        UserDefaults.standard.set(newId, forKey: key)
        return newId
    }

    private func fetchAndRegisterClaudeVersion() {
        // Run file operations in background to avoid blocking main thread
        Task.detached(priority: .background) {
            let claudeProjectsDir = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".claude/projects")

            guard let projectDirs = try? FileManager.default.contentsOfDirectory(
                at: claudeProjectsDir,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: .skipsHiddenFiles
            ) else { return }

            var latestFile: URL?
            var latestDate: Date?

            for projectDir in projectDirs {
                guard let files = try? FileManager.default.contentsOfDirectory(
                    at: projectDir,
                    includingPropertiesForKeys: [.contentModificationDateKey],
                    options: .skipsHiddenFiles
                ) else { continue }

                for file in files where file.pathExtension == "jsonl" && !file.lastPathComponent.hasPrefix("agent-") {
                    if let attrs = try? file.resourceValues(forKeys: [.contentModificationDateKey]),
                       let modDate = attrs.contentModificationDate {
                        if latestDate == nil || modDate > latestDate! {
                            latestDate = modDate
                            latestFile = file
                        }
                    }
                }
            }

            guard let jsonlFile = latestFile,
                  let handle = FileHandle(forReadingAtPath: jsonlFile.path) else { return }
            defer { try? handle.close() }

            let data = handle.readData(ofLength: 8192)
            guard let content = String(data: data, encoding: .utf8) else { return }

            for line in content.components(separatedBy: .newlines) where !line.isEmpty {
                guard let lineData = line.data(using: .utf8),
                      let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                      let version = json["version"] as? String else { continue }

                await MainActor.run {
                    Mixpanel.mainInstance().registerSuperProperties(["claude_code_version": version])
                    Mixpanel.mainInstance().people.set(properties: ["claude_code_version": version])
                }
                return
            }
        }
    }

    private func ensureSingleInstance() -> Bool {
        let bundleID = Bundle.main.bundleIdentifier ?? "com.farouqaldori.ClaudeIsland"
        let runningApps = NSWorkspace.shared.runningApplications.filter {
            $0.bundleIdentifier == bundleID
        }

        if runningApps.count > 1 {
            if let existingApp = runningApps.first(where: { $0.processIdentifier != getpid() }) {
                existingApp.activate()
            }
            return false
        }

        return true
    }
}
