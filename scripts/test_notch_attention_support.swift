import Foundation

struct AnyCodable: @unchecked Sendable {
    let value: Any

    init(_ value: Any) {
        self.value = value
    }
}

@inline(__always)
func assertNotchAttention(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        fputs("Assertion failed: \(message)\n", stderr)
        exit(1)
    }
}

@main
struct NotchAttentionSupportTestRunner {
    static func main() {
        let askUserQuestion = PermissionContext(
            toolUseId: "tool-ask",
            toolName: "AskUserQuestion",
            toolInput: nil,
            receivedAt: Date(timeIntervalSince1970: 1)
        )
        let bashApproval = PermissionContext(
            toolUseId: "tool-bash",
            toolName: "Bash",
            toolInput: nil,
            receivedAt: Date(timeIntervalSince1970: 2)
        )

        assertNotchAttention(
            SessionPhaseHelpers.notchReminderKind(for: .waitingForInput) == .waitingForInput,
            "waiting for input should trigger a prominent notch reminder"
        )
        assertNotchAttention(
            SessionPhaseHelpers.notchReminderKind(for: .waitingForApproval(askUserQuestion)) == .askUserQuestion,
            "AskUserQuestion approvals should trigger the same notch reminder path"
        )
        assertNotchAttention(
            SessionPhaseHelpers.notchReminderKind(for: .waitingForApproval(bashApproval)) == nil,
            "regular tool approvals should keep using the standard pending-permission treatment"
        )

        print("notch attention support checks passed")
    }
}
