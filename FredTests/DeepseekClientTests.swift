import XCTest
@testable import Fred

final class DeepseekClientTests: XCTestCase {
    override func tearDown() {
        URLProtocolMock.handler = nil
        super.tearDown()
    }

    func testSummarizeBuildsCorrectRequestAndParses() async throws {
        var captured: URLRequest?
        URLProtocolMock.handler = { request in
            captured = request
            let body = try JSONDecoder().decode(DeepseekRequest.self, from: URLProtocolMock.bodyData(of: request) ?? Data())
            XCTAssertEqual(body.model, "deepseek-chat")
            XCTAssertEqual(body.response_format?.type, "json_object")
            XCTAssertEqual(body.messages.first?.role, "system")
            XCTAssertTrue(body.messages.last?.content.contains("<TRANSCRICAO>") == true)

            let payload = DeepseekResponse(
                choices: [.init(message: .init(content: "{\"summary\":\"resumo ok\"}"))],
                error: nil
            )
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, try JSONEncoder().encode(payload))
        }

        let client = DeepseekClient(session: .mockSession(), apiKeyProvider: { "chave-teste" })
        let result = try await client.summarize(transcript: "ola")
        XCTAssertEqual(result.summary, "resumo ok")
        XCTAssertEqual(captured?.value(forHTTPHeaderField: "Authorization"), "Bearer chave-teste")
        XCTAssertEqual(captured?.httpMethod, "POST")
    }

    func testReasonerModelUsedForActions() async throws {
        URLProtocolMock.handler = { request in
            let body = try JSONDecoder().decode(DeepseekRequest.self, from: URLProtocolMock.bodyData(of: request) ?? Data())
            XCTAssertEqual(body.model, "deepseek-reasoner")
            let payload = DeepseekResponse(
                choices: [.init(message: .init(content: "{\"summary\":\"s\"}"))],
                error: nil
            )
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, try JSONEncoder().encode(payload))
        }
        let client = DeepseekClient(session: .mockSession(), apiKeyProvider: { "k" })
        let actions = try await client.extractActions(transcript: "x")
        XCTAssertTrue(actions.events.isEmpty)
        XCTAssertTrue(actions.followUps.isEmpty)
    }

    func testMissingAPIKeyThrows() async {
        let client = DeepseekClient(session: .mockSession(), apiKeyProvider: { "" })
        do {
            _ = try await client.summarize(transcript: "x")
            XCTFail("deveria lançar missingAPIKey")
        } catch {
            XCTAssertEqual(error as? DeepseekError, .missingAPIKey)
        }
    }

    func testHTTPErrorThrowsAPIError() async {
        URLProtocolMock.handler = { request in
            (HTTPURLResponse(url: request.url!, statusCode: 429, httpVersion: nil, headerFields: nil)!, Data())
        }
        let client = DeepseekClient(session: .mockSession(), apiKeyProvider: { "k" })
        do {
            _ = try await client.summarize(transcript: "x")
            XCTFail("deveria lançar apiError")
        } catch {
            XCTAssertEqual(error as? DeepseekError, .apiError("HTTP 429"))
        }
    }

    func testEmptyContentThrows() async {
        URLProtocolMock.handler = { request in
            let payload = DeepseekResponse(choices: [.init(message: .init(content: ""))], error: nil)
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, try JSONEncoder().encode(payload))
        }
        let client = DeepseekClient(session: .mockSession(), apiKeyProvider: { "k" })
        do {
            _ = try await client.summarize(transcript: "x")
            XCTFail("deveria lançar emptyContent")
        } catch {
            XCTAssertEqual(error as? DeepseekError, .emptyContent)
        }
    }
}
