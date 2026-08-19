import XCTest
@testable import Fred

final class LoopbackAuthServerTests: XCTestCase {
    // MARK: - Parser puro

    func testParseCodeExtractsCodeAndState() {
        let request = "GET /?code=codigo123&state=estado456 HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n"
        let pair = LoopbackAuthServer.parseCode(from: request)
        XCTAssertEqual(pair?.code, "codigo123")
        XCTAssertEqual(pair?.state, "estado456")
    }

    func testParseCodeWithOnlyPath() {
        let request = "GET /?code=abc&state=def HTTP/1.1\r\n\r\n"
        XCTAssertEqual(LoopbackAuthServer.parseCode(from: request)?.code, "abc")
    }

    func testParseCodeNilWhenMissingState() {
        let request = "GET /?code=abc HTTP/1.1\r\n\r\n"
        XCTAssertNil(LoopbackAuthServer.parseCode(from: request))
    }

    func testParseCodeNilWhenEmptyValues() {
        let request = "GET /?code=&state= HTTP/1.1\r\n\r\n"
        XCTAssertNil(LoopbackAuthServer.parseCode(from: request))
    }

    func testParseCodeNilForNonGET() {
        XCTAssertNil(LoopbackAuthServer.parseCode(from: "POST / HTTP/1.1\r\n\r\n"))
    }

    func testParseCodeNilForGarbage() {
        XCTAssertNil(LoopbackAuthServer.parseCode(from: "isto não é HTTP"))
    }

    func testParseCodeHandlesChunkedRequestLine() {
        // Contrato de acumulação: linha parcial → nil; linha completa → par.
        let partial = "GET /?code=codigo"
        XCTAssertNil(LoopbackAuthServer.parseCode(from: partial), "linha incompleta deve aguardar mais dados")

        let complete = "GET /?code=codigo123&state=estado456 HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n"
        XCTAssertEqual(LoopbackAuthServer.parseCode(from: complete)?.code, "codigo123")
    }

    func testRandomPortIsInEphemeralRange() {
        for _ in 0..<20 {
            let port = LoopbackAuthServer.randomPort()
            XCTAssertTrue((49_152...60_000).contains(Int(port)))
        }
    }

    // MARK: - Loopback real (servidor + GET local)

    func testLiveLoopbackCapturesCode() async throws {
        let port = LoopbackAuthServer.randomPort()
        let server = LoopbackAuthServer(port: port)

        let resultTask = Task {
            try await server.awaitCode(timeout: 10) {
                // Simula o navegador: faz o GET de callback no loopback.
                Task {
                    let url = URL(string: "http://127.0.0.1:\(port)/?code=codigo-real&state=estado-real")!
                    _ = try? await URLSession.shared.data(from: url)
                }
            }
        }

        do {
            let pair = try await resultTask.value
            XCTAssertEqual(pair.code, "codigo-real")
            XCTAssertEqual(pair.state, "estado-real")
        } catch {
            XCTFail("Falha no loopback: \(error)")
        }
    }
}
