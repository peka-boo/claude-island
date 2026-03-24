//
//  SubagentViews.swift
//  ClaudeIsland
//
//  Views for subagent tool lists and summaries.
//

import SwiftUI

/// List of subagent tools (shown during Task execution)
struct SubagentToolsList: View {
    let tools: [SubagentToolCall]

    /// Number of hidden tools (all except last 2)
    private var hiddenCount: Int {
        max(0, tools.count - 2)
    }

    /// Recent tools to show (last 2, regardless of status)
    private var recentTools: [SubagentToolCall] {
        Array(tools.suffix(2))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            // Show count of older hidden tools at top
            if hiddenCount > 0 {
                Text("+\(hiddenCount) more tool uses")
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.4))
            }

            // Show last 2 tools (most recent activity)
            ForEach(recentTools) { tool in
                SubagentToolRow(tool: tool)
            }
        }
    }
}

/// Single subagent tool row
struct SubagentToolRow: View {
    let tool: SubagentToolCall

    @State private var dotOpacity: Double = 0.5

    private var statusColor: Color {
        switch tool.status {
        case .running, .waitingForApproval: return .orange
        case .success: return .green
        case .error, .interrupted: return .red
        }
    }

    /// Get status text using the same logic as regular tools
    private var statusText: String {
        if tool.status == .interrupted {
            return "Interrupted"
        } else if tool.status == .running {
            return ToolStatusDisplay.running(for: tool.name, input: tool.input).text
        } else {
            // For completed subagent tools, we don't have the result data
            // so use a simple display based on tool name and input
            return ToolStatusDisplay.running(for: tool.name, input: tool.input).text
        }
    }

    var body: some View {
        HStack(spacing: 4) {
            // Status dot
            Circle()
                .fill(statusColor.opacity(tool.status == .running ? dotOpacity : 0.6))
                .frame(width: 4, height: 4)
                .id(tool.status)  // Forces view recreation, cancelling repeatForever animation
                .onAppear {
                    if tool.status == .running {
                        withAnimation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true)) {
                            dotOpacity = 0.2
                        }
                    }
                }

            // Tool name
            Text(tool.name)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.white.opacity(0.6))

            // Status text (same format as regular tools)
            Text(statusText)
                .font(.system(size: 10))
                .foregroundColor(.white.opacity(0.5))
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }
}

/// Summary of subagent tools (shown when Task is expanded after completion)
struct SubagentToolsSummary: View {
    let tools: [SubagentToolCall]

    private var toolCounts: [(String, Int)] {
        var counts: [String: Int] = [:]
        for tool in tools {
            counts[tool.name, default: 0] += 1
        }
        return counts.sorted { $0.value > $1.value }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Subagent used \(tools.count) tools:")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.white.opacity(0.5))

            HStack(spacing: 8) {
                ForEach(toolCounts.prefix(5), id: \.0) { name, count in
                    HStack(spacing: 2) {
                        Text(name)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.white.opacity(0.4))
                        Text("×\(count)")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(.white.opacity(0.3))
                    }
                }
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.white.opacity(0.03))
        )
    }
}