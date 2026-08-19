import XCTest
@testable import Fred

final class FredLoggerTests: XCTestCase {
    func testLogWritesLinesToFile() throws {
        let dir = try makeTempDir()
        defer { removeTempDir(dir) }
        let url = dir.appendingPathComponent("fred.log")
        FredLogger.logURLOverride = url
        defer { FredLogger.logURLOverride = nil }

        FredLogger.log("linha um")
        FredLogger.log("linha dois")

        // Aguarda a fila do logger processar.
        let expectation = expectation(description: "log escrito")
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 2)

        let content = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(content.contains("linha um"))
        XCTAssertTrue(content.contains("linha dois"))
    }
}
