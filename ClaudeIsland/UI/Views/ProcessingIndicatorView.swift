//
//  ProcessingIndicatorView.swift
//  ClaudeIsland
//
//  Simple, lightweight processing indicator.
//

import SwiftUI

struct ProcessingIndicatorView: View {
    private let color = Color(red: 0.85, green: 0.47, blue: 0.34) // Claude orange

    // Friendly, varied messages
    private let friendlyMessages = [
        "Thinking",
        "Working",
        "Processing",
        "Analyzing"
    ]

    private let message: String
    @State private var isAnimating = false

    init(turnId: String = "") {
        let index = abs(turnId.hashValue) % friendlyMessages.count
        message = friendlyMessages[index]
    }

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            // Simple pulsing dot
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
                .scaleEffect(isAnimating ? 1.2 : 0.8)
                .opacity(isAnimating ? 1.0 : 0.5)
                .animation(
                    .easeInOut(duration: 0.6)
                    .repeatForever(autoreverses: true),
                    value: isAnimating
                )

            Text(message + "...")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(color.opacity(0.9))

            Spacer()
        }
        .onAppear {
            isAnimating = true
        }
        .onDisappear {
            isAnimating = false
        }
    }
}