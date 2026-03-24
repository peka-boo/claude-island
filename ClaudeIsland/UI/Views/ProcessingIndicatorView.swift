//
//  ProcessingIndicatorView.swift
//  ClaudeIsland
//
//  Animated processing indicator with dots.
//

import SwiftUI
import Combine

struct ProcessingIndicatorView: View {
    private let baseTexts = ["Processing", "Working"]
    private let color = Color(red: 0.85, green: 0.47, blue: 0.34) // Claude orange
    private let baseText: String

    @State private var dotCount: Int = 1
    private let timer = Timer.publish(every: 0.4, on: .main, in: .common).autoconnect()

    /// Use a turnId to select text consistently per user turn
    init(turnId: String = "") {
        // Use hash of turnId to pick base text consistently for this turn
        let index = abs(turnId.hashValue) % baseTexts.count
        baseText = baseTexts[index]
    }

    private var dots: String {
        String(repeating: ".", count: dotCount)
    }

    var body: some View {
        HStack(alignment: .center, spacing: 6) {
            ProcessingSpinner()
                .frame(width: 6)

            Text(baseText + dots)
                .font(.system(size: 13))
                .foregroundColor(color)

            Spacer()
        }
        .onReceive(timer) { _ in
            dotCount = (dotCount % 3) + 1
        }
    }
}