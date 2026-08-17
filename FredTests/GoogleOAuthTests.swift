import XCTest
@testable import Fred

final class GoogleOAuthTests: XCTestCase {
    override func tearDown() {
        URLProtocolMock.handler = nil
        super.tearDown()
    }

    private func makeOAuth(keychain: MockKeychain = MockKeychain()) -> GoogleOAuth {
        GoogleOAuth(
            config: .init(
                clientID: "cid",
                clientSecret: "secret",
                redirectURI: "com.fred.app:/oauth2callback"
            ),
            session: .mockSession(),
            keychain: keychain
        )
    }

    private func seedTokens(_ tokens: GoogleTokens, in keychain: MockKeychain) throws {
        let data = try JSONEncoder().encode(tokens)
        try keychain.set(String(data: data, encoding: .utf8) ?? "", for: "google.tokens")
    }

    func testExchangePersistsTokensAndIncludesPKCE() async throws {
        let keychain = MockKeychain()
        let oauth = makeOAuth(keychain: keychain)
        var capturedBody: String?

        URLProtocolMock.handler = { request in
            capturedBody = String(data: URLProtocolMock.bodyData(of: request) ?? Data(), encoding: .utf8)
            let dto = "{\"access_token\":\"at1\",\"refresh_token\":\"rt1\",\"expires_in\":3600}"
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(dto.utf8))
        }

        let tokens = try await oauth.exchange(code: "código", verifier: "verifier")
        XCTAssertEqual(tokens.accessToken, "at1")
        XCTAssertEqual(tokens.refreshToken, "rt1")
        XCTAssertTrue(capturedBody?.contains("grant_type=authorization_code") == true)
        XCTAssertTrue(capturedBody?.contains("code_verifier=verifier") == true)
        XCTAssertTrue(capturedBody?.contains("client_id=cid") == true)
        XCTAssertTrue(oauth.isSignedIn())
        XCTAssertNotNil(keychain.values["google.tokens"])
    }

    func testExchangeWithoutRefreshTokenThrows() async {
        let oauth = makeOAuth()
        URLProtocolMock.handler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data("{\"access_token\":\"at1\"}".utf8))
        }
        do {
            _ = try await oauth.exchange(code: "c", verifier: "v")
            XCTFail("deveria lançar noRefreshToken")
        } catch {
            XCTAssertEqual(error as? GoogleOAuthError, .noRefreshToken)
        }
    }

    func testRefreshUsesStoredRefreshTokenAndMerges() async throws {
        let keychain = MockKeychain()
        let oauth = makeOAuth(keychain: keychain)
        try seedTokens(
            GoogleTokens(accessToken: "old", refreshToken: "rt-seed", expiresAt: Date().addingTimeInterval(-10)),
            in: keychain
        )
        var capturedBody: String?
        URLProtocolMock.handler = { request in
            capturedBody = String(data: URLProtocolMock.bodyData(of: request) ?? Data(), encoding: .utf8)
            let dto = "{\"access_token\":\"fresh\",\"expires_in\":3600}"
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(dto.utf8))
        }

        let tokens = try await oauth.refreshAccessToken()
        XCTAssertEqual(tokens.accessToken, "fresh")
        XCTAssertEqual(tokens.refreshToken, "rt-seed")
        XCTAssertTrue(capturedBody?.contains("grant_type=refresh_token") == true)
        XCTAssertTrue(capturedBody?.contains("refresh_token=rt-seed") == true)
    }

    func testRefreshWithoutStoredRefreshTokenThrows() async {
        let oauth = makeOAuth()
        do {
            _ = try await oauth.refreshAccessToken()
            XCTFail("deveria lançar noRefreshToken")
        } catch {
            XCTAssertEqual(error as? GoogleOAuthError, .noRefreshToken)
        }
    }

    func testAccessTokenReturnsCachedWhenStillValid() async throws {
        let keychain = MockKeychain()
        let oauth = makeOAuth(keychain: keychain)
        try seedTokens(
            GoogleTokens(accessToken: "valid", refreshToken: "rt", expiresAt: Date().addingTimeInterval(3600)),
            in: keychain
        )
        let token = try await oauth.accessToken()
        XCTAssertEqual(token, "valid")
    }
}
