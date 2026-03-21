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
        HStack(alignment: .bottom, spacing: 10) {
            // Text editor
            ZStack(alignment: .topLeading) {
                if text.isEmpty {
                    Text("Message Claude...")
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.4))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 8)
                }

                TextEditor(text: $text)
                    .font(.system(size: 13))
                    .foregroundStyle(.white)
                    .scrollContentBackground(.hidden)
                    .focused($isFocused)
                    .frame(minHeight: 32, maxHeight: 120)
                    .fixedSize(horizontal: false, vertical: true)
                    .onSubmit {
                        // Cmd+Enter to send
                    }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.white.opacity(0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .strokeBorder(Color.white.opacity(0.15), lineWidth: 1)
                    )
            )

            // Action button
            VStack(spacing: 4) {
                if isProcessing {
                    Button {
                        onInterrupt()
                    } label: {
                        Image(systemName: "stop.circle.fill")
                            .font(.system(size: 26))
                            .foregroundStyle(TerminalColors.red)
                    }
                    .buttonStyle(.plain)
                    .help("Stop (⌘.)")
                } else {
                    Button {
                        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                        onSend()
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 26))
                            .foregroundStyle(
                                text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                ? .white.opacity(0.2) : .white.opacity(0.9)
                            )
                    }
                    .buttonStyle(.plain)
                    .help("Send (⌘↩)")
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding(.bottom, 6)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.black.opacity(0.3))
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
