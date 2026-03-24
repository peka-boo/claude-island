//
//  InteractivePromptBars.swift
//  ClaudeIsland
//
//  Interactive prompt bars for handling AskUserQuestion and other interactive tools.
//

import SwiftUI

struct ChatStructuredInteractivePromptBar: View {
    let prompt: AskUserQuestionPrompt
    let isSending: Bool
    let errorMessage: String?
    let onSubmit: (AskUserQuestionSubmission) -> Void

    @State private var selectedOptions: [String: [String]] = [:]
    @State private var customAnswers: [String: String] = [:]

    private var draftAnswers: [String: AskUserQuestionDraftAnswer] {
        Dictionary(uniqueKeysWithValues: prompt.questions.map { question in
            (
                question.question,
                AskUserQuestionDraftAnswer(
                    selectedOptionLabels: selectedOptions[question.question] ?? [],
                    customAnswer: trimmedCustomAnswer(for: question),
                    notes: nil
                )
            )
        })
    }

    private var isComplete: Bool {
        prompt.questions.allSatisfy { question in
            AskUserQuestionWizardSupport.canAdvance(
                question: question,
                draft: draftAnswers[question.question]
            )
        }
    }

    private var submission: AskUserQuestionSubmission? {
        guard isComplete else { return nil }
        return AskUserQuestionSubmissionBuilder.build(prompt: prompt, drafts: draftAnswers)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text(MCPToolFormatter.formatToolName("AskUserQuestion"))
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundColor(TerminalColors.amber)

                Text("\(prompt.questions.count) question\(prompt.questions.count == 1 ? "" : "s")")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.45))
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(Array(prompt.questions.enumerated()), id: \.element.id) { index, question in
                        structuredQuestionSection(question, index: index)
                    }
                }
            }
            .frame(maxHeight: 220)
            .scrollIndicators(.never)

            if let errorMessage, !errorMessage.isEmpty {
                Text(errorMessage)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.red.opacity(0.85))
            }

            Button {
                if let submission {
                    onSubmit(submission)
                }
            } label: {
                HStack(spacing: 6) {
                    if isSending {
                        ProgressView()
                            .controlSize(.small)
                            .tint(.black)
                    }
                    Text(isSending ? "Sending..." : "Send Answer")
                        .font(.system(size: 13, weight: .semibold))
                }
                .foregroundColor(.black)
                .padding(.horizontal, 16)
                .padding(.vertical, 9)
                .background((submission != nil && !isSending) ? Color.white.opacity(0.95) : Color.white.opacity(0.14))
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(submission == nil || isSending)
        }
        .frame(minHeight: 44)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.black.opacity(0.2))
    }

    @ViewBuilder
    private func structuredQuestionSection(_ question: AskUserQuestionPromptItem, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(AskUserQuestionWizardSupport.stepTitle(for: question, index: index).uppercased())
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundColor(.white.opacity(0.35))

            Text(question.question)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white.opacity(0.88))

            VStack(alignment: .leading, spacing: 6) {
                ForEach(question.options) { option in
                    Button {
                        toggleOption(option, in: question)
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 8) {
                                Image(systemName: isSelected(option, in: question) ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(isSelected(option, in: question) ? TerminalColors.green : .white.opacity(0.35))

                                Text(option.displayLabel)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.white.opacity(0.9))
                            }

                            if let description = option.description, !description.isEmpty {
                                Text(description)
                                    .font(.system(size: 11))
                                    .foregroundColor(.white.opacity(0.45))
                                    .padding(.leading, 20)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(isSelected(option, in: question) ? Color.white.opacity(0.10) : Color.white.opacity(0.04))
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            TextField("Custom answer (optional)", text: Binding(
                get: { customAnswers[question.question, default: ""] },
                set: { customAnswers[question.question] = $0 }
            ))
            .textFieldStyle(.plain)
            .font(.system(size: 12))
            .foregroundColor(.white.opacity(0.88))
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.white.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                    )
            )
        }
    }

    private func isSelected(_ option: AskUserQuestionPromptOption, in question: AskUserQuestionPromptItem) -> Bool {
        (selectedOptions[question.question] ?? []).contains(option.rawLabel)
    }

    private func toggleOption(_ option: AskUserQuestionPromptOption, in question: AskUserQuestionPromptItem) {
        var selected = selectedOptions[question.question] ?? []

        if question.multiSelect {
            if let existingIndex = selected.firstIndex(of: option.rawLabel) {
                selected.remove(at: existingIndex)
            } else {
                selected.append(option.rawLabel)
            }
        } else {
            selected = selected == [option.rawLabel] ? [] : [option.rawLabel]
        }

        selectedOptions[question.question] = selected
    }

    private func trimmedCustomAnswer(for question: AskUserQuestionPromptItem) -> String? {
        let trimmed = customAnswers[question.question, default: ""]
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

/// Bar for interactive tools like AskUserQuestion that can be answered inline.
struct ChatInteractivePromptBar: View {
    let toolInput: String?
    @Binding var replyText: String
    let isSending: Bool
    let errorMessage: String?
    let onSubmit: () -> Void
    let onGoToTerminal: () -> Void

    @State private var showContent = false
    @State private var showButton = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(MCPToolFormatter.formatToolName("AskUserQuestion"))
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundColor(TerminalColors.amber)
                    Text(toolInput ?? "Claude Code needs your input")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.5))
                        .lineLimit(3)
                }
                .opacity(showContent ? 1 : 0)
                .offset(x: showContent ? 0 : -10)

                Spacer()

                Button {
                    onGoToTerminal()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "terminal")
                            .font(.system(size: 11, weight: .medium))
                        Text("Terminal")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .foregroundColor(.white.opacity(0.8))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color.white.opacity(0.1))
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .opacity(showButton ? 1 : 0)
                .scaleEffect(showButton ? 1 : 0.8)
            }

            HStack(spacing: 8) {
                TextField("Reply to Claude...", text: $replyText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.9))
                    .disabled(isSending)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.white.opacity(0.06))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
                            )
                    )
                    .onSubmit(onSubmit)

                Button {
                    onSubmit()
                } label: {
                    HStack(spacing: 6) {
                        if isSending {
                            ProgressView()
                                .controlSize(.small)
                                .tint(.black)
                        }
                        Image(systemName: "arrow.up")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundColor(.black)
                    .frame(width: 38, height: 38)
                    .background(
                        (replyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSending)
                            ? Color.white.opacity(0.16)
                            : Color.white.opacity(0.95)
                    )
                    .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .disabled(replyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSending)
            }

            if let errorMessage, !errorMessage.isEmpty {
                Text(errorMessage)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.red.opacity(0.85))
            }
        }
        .frame(minHeight: 44)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.black.opacity(0.2))
        .onAppear {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7).delay(0.05)) {
                showContent = true
            }
            withAnimation(.spring(response: 0.35, dampingFraction: 0.7).delay(0.1)) {
                showButton = true
            }
        }
    }
}