import Foundation

extension XCTestCase {
    func XCTAssertNoThrow<T>(
        _ expression: @autoclosure () throws -> T,
        _ message: @autoclosure () -> String = "",
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> T? {
        do {
            return try expression()
        } catch {
            XCTFail("Threw error: \(error) - \(message())", file: file, line: line)
            return nil
        }
    }
}
