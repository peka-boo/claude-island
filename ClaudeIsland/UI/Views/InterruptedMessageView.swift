//
//  InterruptedMessageView.swift
//  ClaudeIsland
//
//  Interrupted message indicator.
//

import SwiftUI

struct InterruptedMessageView: View {
    var body: some View {
        HStack {
            Text("Interrupted")
                .font(.system(size: 13))
                .foregroundColor(.red)
            Spacer()
        }
    }
}