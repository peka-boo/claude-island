import Foundation

func assertDetailIdentity(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        fputs("Assertion failed: \(message)\n", stderr)
        exit(1)
    }
}

@main
struct MainWindowDetailIdentitySupportTestRunner {
    static func main() {
        let firstChatIdentity = MainWindowDetailIdentitySupport.identity(for: "thread-1")
        let secondChatIdentity = MainWindowDetailIdentitySupport.identity(for: "thread-2")
        let welcomeIdentity = MainWindowDetailIdentitySupport.identity(for: nil)

        assertDetailIdentity(
            firstChatIdentity == "chat",
            "chat detail should use a stable identity instead of resetting per thread"
        )
        assertDetailIdentity(
            secondChatIdentity == "chat",
            "switching between chat threads should retain the same chat identity"
        )
        assertDetailIdentity(
            welcomeIdentity == "welcome",
            "the welcome state should keep its own identity"
        )

        print("main window detail identity checks passed")
    }
}
