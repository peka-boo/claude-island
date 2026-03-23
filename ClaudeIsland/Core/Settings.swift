//
//  Settings.swift
//  ClaudeIsland
//
//  App settings manager using UserDefaults
//

import Foundation

/// Available notification sounds
enum NotificationSound: String, CaseIterable {
    case none = "None"
    case pop = "Pop"
    case ping = "Ping"
    case tink = "Tink"
    case glass = "Glass"
    case blow = "Blow"
    case bottle = "Bottle"
    case frog = "Frog"
    case funk = "Funk"
    case hero = "Hero"
    case morse = "Morse"
    case purr = "Purr"
    case sosumi = "Sosumi"
    case submarine = "Submarine"
    case basso = "Basso"

    /// The system sound name to use with NSSound, or nil for no sound
    var soundName: String? {
        self == .none ? nil : rawValue
    }
}

enum AppSettings {
    private static let defaults = UserDefaults.standard

    // MARK: - Keys

    private enum Keys {
        static let notificationSound = "notificationSound"
        static let notchEnabled = "notchEnabled"
        static let desktopMessageEnabled = "desktopMessageEnabled"
        static let desktopMessageCollapsed = "desktopMessageCollapsed"
        static let hookMonitorEnabled = "hookMonitorEnabled"
        static let serverPort = "serverPort"
    }

    // MARK: - Notification Sound

    /// The sound to play when Claude finishes and is ready for input
    static var notificationSound: NotificationSound {
        get {
            guard let rawValue = defaults.string(forKey: Keys.notificationSound),
                  let sound = NotificationSound(rawValue: rawValue) else {
                return .pop // Default to Pop
            }
            return sound
        }
        set {
            defaults.set(newValue.rawValue, forKey: Keys.notificationSound)
        }
    }

    // MARK: - Dynamic Island (Notch)

    /// Whether the Notch overlay is enabled
    static var notchEnabled: Bool {
        get {
            if defaults.object(forKey: Keys.notchEnabled) == nil,
               defaults.object(forKey: Keys.desktopMessageEnabled) == nil {
                return ClaudeMessageDisplaySupport.defaultHookDisplayMode == .notch
            }
            return defaults.object(forKey: Keys.notchEnabled) as? Bool ?? false
        }
        set { defaults.set(newValue, forKey: Keys.notchEnabled) }
    }

    static func setNotchEnabled(_ enabled: Bool) {
        notchEnabled = enabled
        NotificationCenter.default.post(
            name: .notchToggled,
            object: nil,
            userInfo: ["enabled": enabled]
        )
    }

    // MARK: - Desktop Message

    /// Whether claude hook Popup mode is selected
    static var desktopMessageEnabled: Bool {
        get {
            if defaults.object(forKey: Keys.desktopMessageEnabled) == nil,
               defaults.object(forKey: Keys.notchEnabled) == nil {
                return ClaudeMessageDisplaySupport.defaultHookDisplayMode == .popup
            }
            return defaults.object(forKey: Keys.desktopMessageEnabled) as? Bool ?? false
        }
        set { defaults.set(newValue, forKey: Keys.desktopMessageEnabled) }
    }

    /// Whether the floating desktop surface is currently collapsed
    static var desktopMessageCollapsed: Bool {
        get { defaults.object(forKey: Keys.desktopMessageCollapsed) as? Bool ?? false }
        set { defaults.set(newValue, forKey: Keys.desktopMessageCollapsed) }
    }

    static func setDesktopMessageEnabled(_ enabled: Bool) {
        desktopMessageEnabled = enabled
        if !enabled {
            desktopMessageCollapsed = false
        }

        NotificationCenter.default.post(
            name: .desktopMessageToggled,
            object: nil,
            userInfo: ["enabled": enabled]
        )

        if !enabled {
            NotificationCenter.default.post(
                name: .desktopMessageCollapsedToggled,
                object: nil,
                userInfo: ["collapsed": false]
            )
        }
    }

    static func setDesktopMessageCollapsed(_ collapsed: Bool) {
        let resolvedCollapsed = desktopMessageEnabled ? collapsed : false
        desktopMessageCollapsed = resolvedCollapsed
        NotificationCenter.default.post(
            name: .desktopMessageCollapsedToggled,
            object: nil,
            userInfo: ["collapsed": resolvedCollapsed]
        )
    }

    static var claudeHookDisplayMode: ClaudeHookDisplayMode {
        if defaults.object(forKey: Keys.notchEnabled) == nil,
           defaults.object(forKey: Keys.desktopMessageEnabled) == nil {
            return ClaudeMessageDisplaySupport.defaultHookDisplayMode
        }

        return notchEnabled ? .notch : .popup
    }

    static func setClaudeHookDisplayMode(_ mode: ClaudeHookDisplayMode) {
        let state = ClaudeMessageDisplaySupport.settingsState(for: mode)
        notchEnabled = state.notchEnabled
        desktopMessageEnabled = state.popupEnabled
        desktopMessageCollapsed = false

        NotificationCenter.default.post(
            name: .notchToggled,
            object: nil,
            userInfo: ["enabled": state.notchEnabled]
        )
        NotificationCenter.default.post(
            name: .desktopMessageToggled,
            object: nil,
            userInfo: ["enabled": state.popupEnabled]
        )
        NotificationCenter.default.post(
            name: .desktopMessageCollapsedToggled,
            object: nil,
            userInfo: ["collapsed": false]
        )
    }

    // MARK: - Hook Monitor

    /// Whether the global Hook Monitor is enabled (captures all CLI sessions)
    static var hookMonitorEnabled: Bool {
        get { defaults.object(forKey: Keys.hookMonitorEnabled) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Keys.hookMonitorEnabled) }
    }

    static func setHookMonitorEnabled(_ enabled: Bool) {
        hookMonitorEnabled = enabled
        NotificationCenter.default.post(
            name: .hookMonitorToggled,
            object: nil,
            userInfo: ["enabled": enabled]
        )
    }

    // MARK: - HTTP Server Port

    /// Default HTTP server port for Hook events
    static let defaultServerPort: UInt16 = 49152

    /// Current HTTP server port
    static var serverPort: UInt16 {
        get {
            let value = defaults.integer(forKey: Keys.serverPort)
            return value > 0 ? UInt16(value) : defaultServerPort
        }
        set { defaults.set(Int(newValue), forKey: Keys.serverPort) }
    }
}

extension Notification.Name {
    static let notchToggled = Notification.Name("notchToggled")
    static let desktopMessageToggled = Notification.Name("desktopMessageToggled")
    static let desktopMessageCollapsedToggled = Notification.Name("desktopMessageCollapsedToggled")
    static let hookMonitorToggled = Notification.Name("hookMonitorToggled")
}
