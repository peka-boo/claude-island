//
//  MessageInputView.swift
//  ClaudeIsland
//
//  Text input area with send/interrupt actions.
//

import SwiftUI

struct MessageInputView: View {
    @Binding var text: String
    let isProcessing: Bool
    let onSend: () -> Void
    let onInterrupt: () -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            // Text editor
            ZStack(alignment: .topLeading) {
                if text.isEmpty {
                    Text("Message Claude...")
                        .font(.system(size: 13))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 8)
                }

                TextEditor(text: $text)
                    .font(.system(size: 13))
                    .scrollContentBackground(.hidden)
                    .focused($isFocused)
                    .frame(minHeight: 32, maxHeight: 120)
                    .fixedSize(horizontal: false, vertical: true)
                    .onSubmit {
                        // Cmd+Enter to send
                    }
            }

            // Action button
            VStack(spacing: 4) {
                if isProcessing {
                    Button {
                        onInterrupt()
                    } label: {
                        Image(systemName: "stop.circle.fill")
                            .font(.system(size: 22))
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                    .help("Stop Claude (⌘.)")
                } else {
                    Button {
                        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                        onSend()
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 22))
                            .foregroundStyle(
                                text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                ? .gray : .accentColor
                            )
                    }
                    .buttonStyle(.plain)
                    .help("Send (⌘↩)")
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding(.bottom, 4)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
        .onAppear {
            isFocused = true
        }
        .onKeyPress(.return, phases: .down) { press in
            if press.modifiers.contains(.command) {
                guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    return .ignored
                }
                onSend()
                return .handled
            }
            return .ignored
        }
        .onKeyPress(KeyEquivalent("."), phases: .down) { press in
            if press.modifiers.contains(.command) && isProcessing {
                onInterrupt()
                return .handled
            }
            return .ignored
        }
    }
}
