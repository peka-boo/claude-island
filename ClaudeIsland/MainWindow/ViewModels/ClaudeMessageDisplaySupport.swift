//
//  ClaudeMessageDisplaySupport.swift
//  ClaudeIsland
//
//  Shared display rules for the claude-message surfaces.
//

import CoreGraphics
import Foundation

enum ClaudeHookDisplayMode: String, CaseIterable, Equatable {
    case notch
    case popup
}

struct ClaudeHookSettingsState: Equatable {
    let notchEnabled: Bool
    let popupEnabled: Bool
}

enum ClaudeMessageDesktopSurface: Equatable {
    case hidden
    case expanded
    case collapsed
}

enum ClaudeMessageWindowContentMode: Equatable {
    case workspace
    case compactPanel
}

struct ClaudeMessageWindowLayout: Equatable {
    let contentMode: ClaudeMessageWindowContentMode
    let size: CGSize
}

enum ClaudeMessageDisplaySupport {
    static let defaultHookDisplayMode: ClaudeHookDisplayMode = .popup
    static let expandedWindowSize = CGSize(width: 1168, height: 720)
    static let collapsedWindowSize = CGSize(width: 360, height: 160)

    static func settingsState(for mode: ClaudeHookDisplayMode) -> ClaudeHookSettingsState {
        switch mode {
        case .notch:
            return ClaudeHookSettingsState(
                notchEnabled: true,
                popupEnabled: false
            )
        case .popup:
            return ClaudeHookSettingsState(
                notchEnabled: false,
                popupEnabled: true
            )
        }
    }

    static func menuTitle(for mode: ClaudeHookDisplayMode) -> String {
        switch mode {
        case .notch:
            return "Current Notch"
        case .popup:
            return "Popup"
        }
    }

    static func desktopSurface(isEnabled: Bool, isCollapsed: Bool) -> ClaudeMessageDesktopSurface {
        guard isEnabled else { return .hidden }
        return isCollapsed ? .collapsed : .expanded
    }

    static func collapseActionTitle(isDesktopEnabled: Bool, isCollapsed: Bool) -> String? {
        guard isDesktopEnabled else { return nil }
        return isCollapsed ? "Expand" : "Collapse"
    }

    static func windowLayout(isDesktopEnabled: Bool, isCollapsed: Bool) -> ClaudeMessageWindowLayout {
        switch desktopSurface(isEnabled: isDesktopEnabled, isCollapsed: isCollapsed) {
        case .hidden, .expanded:
            return ClaudeMessageWindowLayout(
                contentMode: .workspace,
                size: expandedWindowSize
            )
        case .collapsed:
            return ClaudeMessageWindowLayout(
                contentMode: .compactPanel,
                size: collapsedWindowSize
            )
        }
    }
}
