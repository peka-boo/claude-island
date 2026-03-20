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
        get { defaults.object(forKey: Keys.notchEnabled) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Keys.notchEnabled) }
    }

    // MARK: - Hook Monitor

    /// Whether the global Hook Monitor is enabled (captures all CLI sessions)
    static var hookMonitorEnabled: Bool {
        get { defaults.object(forKey: Keys.hookMonitorEnabled) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Keys.hookMonitorEnabled) }
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
