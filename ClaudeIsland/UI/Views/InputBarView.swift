//
//  InputBarView.swift
//  ClaudeIsland
//
//  Input bar for chat messages with interrupt support.
//

import SwiftUI

struct InputBarView: View {
    let messageSendError: String?
    let messageTransport: SessionMessageTransport
    let canSendMessages: Bool
    @Binding var inputText: String
    let isInputFocused: FocusState<Bool>.Binding
    let isSendingMessage: Bool
    let isProcessing: Bool
    let sendMessage: () -> Void
    let interruptSession: () -> Void

    private let fadeColor = Color(red: 0.00, green: 0.00, blue: 0.00)

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let messageSendError, !messageSendError.isEmpty {
                Text(messageSendError)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.red.opacity(0.85))
                    .padding(.horizontal, 4)
            }

            HStack(spacing: 10) {
                TextField(SessionMessageTransportSupport.placeholder(for: messageTransport), text: $inputText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundColor(canSendMessages ? .white : .white.opacity(0.4))
                    .focused(isInputFocused)
                    .disabled(!canSendMessages)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 20)
                            .fill(Color.white.opacity(canSendMessages ? 0.08 : 0.04))
                            .overlay(
                                RoundedRectangle(cornerRadius: 20)
                                    .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
                            )
                    )
                    .onSubmit {
                        if !isProcessing {
                            sendMessage()
                        }
                    }

                // Interrupt button when processing
                if isProcessing {
                    Button {
                        interruptSession()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "stop.circle.fill")
                                .font(.system(size: 14))
                            Text("Stop")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .foregroundColor(.white.opacity(0.7))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            Capsule()
                                .fill(Color.red.opacity(0.3))
                        )
                    }
                    .buttonStyle(.plain)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 0.8)),
                        removal: .opacity
                    ))
                }

                Button {
                    sendMessage()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 28))
                        .foregroundColor(!canSendMessages || inputText.isEmpty || isSendingMessage ? .white.opacity(0.2) : .white.opacity(0.9))
                }
                .buttonStyle(.plain)
                .disabled(!canSendMessages || inputText.isEmpty || isSendingMessage)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.black.opacity(0.2))
        .overlay(alignment: .top) {
            LinearGradient(
                colors: [fadeColor.opacity(0), fadeColor.opacity(0.7)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 24)
            .offset(y: -24)
            .allowsHitTesting(false)
        }
        .zIndex(1)
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: isProcessing)
    }
}