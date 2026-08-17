import XCTest
@testable import Fred

final class CalendarAPITests: XCTestCase {
    override func tearDown() {
        URLProtocolMock.handler = nil
        super.tearDown()
    }

    private func makeDraft(status: EventDraftStatus) -> EventDraft {
        EventDraft(
            id: UUID(),
            recordingID: UUID(),
            title: "Sync",
            startDate: Date().addingTimeInterval(3600),
            endDate: Date().addingTimeInterval(7200),
            timeZone: "America/Sao_Paulo",
            notes: nil,
            googleEventID: nil,
            status: status
        )
    }

    private func makeAPI() -> GoogleCalendarAPI {
        let keychain = MockKeychain()
        let tokens = GoogleTokens(accessToken: "tok", refreshToken: "rt", expiresAt: Date().addingTimeInterval(3600))
        let data = try! JSONEncoder().encode(tokens)
        try! keychain.set(String(data: data, encoding: .utf8) ?? "", for: "google.tokens")
        let oauth = GoogleOAuth(
            config: .init(clientID: "cid", clientSecret: "secret", redirectURI: "com.fred.app:/oauth2callback"),
            session: .mockSession(),
            keychain: keychain
        )
        return GoogleCalendarAPI(session: .mockSession(), oauth: oauth)
    }

    /// REGRA DE SEGURANÇA: evento nunca é criado sem confirmação manual.
    func testProposedDraftIsRejected() async {
        let api = makeAPI()
        do {
            _ = try await api.createEvent(makeDraft(status: .proposed))
            XCTFail("deveria bloquear evento não confirmado")
        } catch {
            XCTAssertEqual(error as? CalendarAPIError, .eventCreatedWithoutConfirmation)
        }
    }

    func testConfirmedDraftPostsPayloadAndReturnsEventID() async throws {
        let api = makeAPI()
        var captured: URLRequest?
        URLProtocolMock.handler = { request in
            captured = request
            let payload = try JSONDecoder().decode(GoogleCalendarAPI.EventPayload.self, from: URLProtocolMock.bodyData(of: request) ?? Data())
            XCTAssertEqual(payload.summary, "Sync")
            XCTAssertEqual(payload.start.timeZone, "America/Sao_Paulo")
            XCTAssertEqual(payload.end.timeZone, "America/Sao_Paulo")
            XCTAssertTrue(payload.start.dateTime.contains("T"))
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data("{\"id\":\"evt-123\"}".utf8))
        }

        let eventID = try await api.createEvent(makeDraft(status: .confirmed))
        XCTAssertEqual(eventID, "evt-123")
        XCTAssertEqual(captured?.value(forHTTPHeaderField: "Authorization"), "Bearer tok")
        XCTAssertEqual(captured?.httpMethod, "POST")
        XCTAssertTrue(captured?.url?.path.contains("/calendars/primary/events") == true)
    }

    func testHTTPErrorPropagates() async {
        let api = makeAPI()
        URLProtocolMock.handler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }
        do {
            _ = try await api.createEvent(makeDraft(status: .confirmed))
            XCTFail("deveria lançar http(500)")
        } catch {
            XCTAssertEqual(error as? CalendarAPIError, .http(500))
        }
    }
}
