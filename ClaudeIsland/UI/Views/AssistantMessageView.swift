//
//  AssistantMessageView.swift
//  ClaudeIsland
//
//  Assistant message bubble view.
//

import SwiftUI

struct AssistantMessageView: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            // White dot indicator
            Circle()
                .fill(Color.white.opacity(0.6))
                .frame(width: 6, height: 6)
                .padding(.top, 5)

            MarkdownText(text, color: .white.opacity(0.9), fontSize: 13)

            Spacer(minLength: 60)
        }
    }
}