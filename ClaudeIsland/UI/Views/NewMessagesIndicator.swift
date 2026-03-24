//
//  NewMessagesIndicator.swift
//  ClaudeIsland
//
//  Floating indicator showing count of new messages when user has scrolled up.
//

import SwiftUI

struct NewMessagesIndicator: View {
    let count: Int
    let onTap: () -> Void

    @State private var isHovering: Bool = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 6) {
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .bold))

                Text(count == 1 ? "1 new message" : "\(count) new messages")
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(Color(red: 0.85, green: 0.47, blue: 0.34)) // Claude orange
                    .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 4)
            )
            .scaleEffect(isHovering ? 1.05 : 1.0)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.spring(response: 0.2, dampingFraction: 0.7)) {
                isHovering = hovering
            }
        }
    }
}