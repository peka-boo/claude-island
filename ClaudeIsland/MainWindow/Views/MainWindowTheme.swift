//
//  MainWindowTheme.swift
//  ClaudeIsland
//
//  Shared visual language for the main window, aligned with the notch UI.
//

import SwiftUI

enum MainWindowTheme {
    static let uiScale: CGFloat = 0.8
    static var conversationColumnMaxWidth: CGFloat { scaled(1188) }
    static let backgroundTop = Color(red: 0.11, green: 0.09, blue: 0.08)
    static let backgroundBottom = Color(red: 0.03, green: 0.03, blue: 0.03)
    static let backgroundWarmGlow = Color(red: 0.46, green: 0.28, blue: 0.18)
    static let backgroundCoolGlow = Color(red: 0.20, green: 0.30, blue: 0.42)
    static let sidebarRail = Color(red: 0.12, green: 0.10, blue: 0.09)
    static let sidebarPanel = Color(red: 0.11, green: 0.09, blue: 0.08)
    static let workspace = Color(red: 0.02, green: 0.02, blue: 0.02)
    static let panel = Color.white.opacity(0.04)
    static let panelElevated = Color.white.opacity(0.062)
    static let panelHover = Color.white.opacity(0.08)
    static let panelSelected = Color.white.opacity(0.10)
    static let border = Color.white.opacity(0.06)
    static let borderStrong = Color.white.opacity(0.13)
    static let separator = Color.white.opacity(0.06)
    static let textPrimary = Color.white.opacity(0.92)
    static let textSecondary = Color.white.opacity(0.64)
    static let textMuted = Color.white.opacity(0.34)
    static let accent = Color(red: 0.85, green: 0.47, blue: 0.34)
    static let hoverFill = Color.white.opacity(0.08)
    static let hoverAnimation = Animation.spring(response: 0.26, dampingFraction: 0.86)
    static let selectionAnimation = Animation.spring(response: 0.32, dampingFraction: 0.84)
    static let entranceAnimation = Animation.spring(response: 0.42, dampingFraction: 0.82)
    static let panelOpenAnimation = Animation.spring(response: 0.38, dampingFraction: 0.84)
    static let panelCloseAnimation = Animation.easeOut(duration: 0.18)
    static let contentSwapAnimation = Animation.spring(response: 0.36, dampingFraction: 0.88)
    static let softFadeAnimation = Animation.easeOut(duration: 0.2)

    static let floatingCardTransition = AnyTransition.asymmetric(
        insertion: .opacity
            .combined(with: .move(edge: .bottom))
            .combined(with: .scale(scale: 0.985, anchor: .bottom)),
        removal: .opacity
            .combined(with: .scale(scale: 0.985, anchor: .bottom))
    )

    static let sectionRevealTransition = AnyTransition.asymmetric(
        insertion: .opacity
            .combined(with: .move(edge: .top))
            .combined(with: .scale(scale: 0.99, anchor: .top)),
        removal: .opacity
            .combined(with: .scale(scale: 0.99, anchor: .top))
    )

    static let detailSwapTransition = AnyTransition.asymmetric(
        insertion: .opacity
            .combined(with: .move(edge: .trailing))
            .combined(with: .scale(scale: 0.992, anchor: .center)),
        removal: .opacity
            .combined(with: .scale(scale: 0.992, anchor: .center))
    )

    static func scaled(_ value: CGFloat) -> CGFloat {
        value * uiScale
    }

    static func adaptiveAnimation(_ animation: Animation, reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : animation
    }

    static func adaptiveTransition(_ transition: AnyTransition, reduceMotion: Bool) -> AnyTransition {
        reduceMotion ? .opacity : transition
    }
}

struct MainWindowBackdrop: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [MainWindowTheme.backgroundTop, MainWindowTheme.backgroundBottom],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RadialGradient(
                colors: [
                    MainWindowTheme.backgroundWarmGlow.opacity(0.22),
                    .clear
                ],
                center: .topTrailing,
                startRadius: 18,
                endRadius: 420
            )

            RadialGradient(
                colors: [
                    MainWindowTheme.backgroundCoolGlow.opacity(0.14),
                    .clear
                ],
                center: .bottomLeading,
                startRadius: 12,
                endRadius: 360
            )
        }
        .ignoresSafeArea()
    }
}

extension View {
    func mainWindowCard(
        fill: Color = MainWindowTheme.panel,
        border: Color = MainWindowTheme.border,
        radius: CGFloat = 18,
        shadowOpacity: Double = 0.16
    ) -> some View {
        background(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(fill)
                .overlay(
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .strokeBorder(border, lineWidth: 1)
                )
                .shadow(color: .black.opacity(shadowOpacity), radius: 24, x: 0, y: 14)
        )
    }

    func mainWindowHairline(_ color: Color = MainWindowTheme.separator) -> some View {
        overlay(alignment: .bottom) {
            Rectangle()
                .fill(color)
                .frame(height: 1)
        }
    }

    func revealTransition(show: Bool, x: CGFloat = 0, y: CGFloat = 8) -> some View {
        opacity(show ? 1 : 0)
            .offset(x: show ? 0 : x, y: show ? 0 : y)
            .scaleEffect(show ? 1 : 0.988, anchor: .top)
            .animation(MainWindowTheme.entranceAnimation, value: show)
    }
}
