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
        XCTAssertTrue(capturedBody?.contains("client_secret=secret") == true, "secret presente quando configurado")
        XCTAssertTrue(oauth.isSignedIn())
        XCTAssertNotNil(keychain.values["google.tokens"])
    }

    func testExchangeWithoutClientSecretOmitsItFromBody() async throws {
        let keychain = MockKeychain()
        let oauth = GoogleOAuth(
            config: .init(clientID: "cid", clientSecret: nil, redirectURI: "com.fred.app:/oauth2callback"),
            session: .mockSession(),
            keychain: keychain
        )
        var capturedBody: String?
        URLProtocolMock.handler = { request in
            capturedBody = String(data: URLProtocolMock.bodyData(of: request) ?? Data(), encoding: .utf8)
            let dto = "{\"access_token\":\"at1\",\"refresh_token\":\"rt1\",\"expires_in\":3600}"
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(dto.utf8))
        }
        _ = try await oauth.exchange(code: "c", verifier: "v")
        XCTAssertTrue(capturedBody?.contains("client_id=cid") == true)
        XCTAssertTrue(capturedBody?.contains("code_verifier=v") == true)
        XCTAssertFalse(capturedBody?.contains("client_secret") == true, "PKCE dispensa o secret")
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

    // MARK: - URL de autorização (loopback)

    func testAuthorizationURLContainsPKCEAndLoopbackRedirect() throws {
        let oauth = makeOAuth()
        let url = try oauth.authorizationURL(
            redirectURI: "http://127.0.0.1:5173",
            challenge: "challenge",
            state: "state123"
        )
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let items = components.queryItems ?? []
        func value(_ name: String) -> String? {
            items.first { $0.name == name }?.value
        }
        XCTAssertEqual(value("client_id"), "cid")
        XCTAssertEqual(value("redirect_uri"), "http://127.0.0.1:5173")
        XCTAssertEqual(value("response_type"), "code")
        XCTAssertEqual(value("code_challenge"), "challenge")
        XCTAssertEqual(value("code_challenge_method"), "S256")
        XCTAssertEqual(value("state"), "state123")
        XCTAssertEqual(value("access_type"), "offline")
        XCTAssertEqual(value("scope"), "openid email https://www.googleapis.com/auth/calendar.events")
    }

    func testExchangeWithExplicitRedirectOverridesConfig() async throws {
        let keychain = MockKeychain()
        let oauth = makeOAuth(keychain: keychain)
        var capturedBody: String?
        URLProtocolMock.handler = { request in
            capturedBody = String(data: URLProtocolMock.bodyData(of: request) ?? Data(), encoding: .utf8)
            let dto = "{\"access_token\":\"at1\",\"refresh_token\":\"rt1\",\"expires_in\":3600}"
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(dto.utf8))
        }
        _ = try await oauth.exchange(code: "c", verifier: "v", redirectURI: "http://127.0.0.1:9999")
        XCTAssertTrue(capturedBody?.contains("redirect_uri=http://127.0.0.1:9999") == true)
    }

    func testTokenEndpointErrorIncludesGoogleDetail() async {
        let oauth = makeOAuth()
        URLProtocolMock.handler = { request in
            let body = "{\"error\":\"invalid_grant\",\"error_description\":\"Malformed auth code.\"}"
            let response = HTTPURLResponse(url: request.url!, statusCode: 400, httpVersion: nil, headerFields: nil)!
            return (response, Data(body.utf8))
        }
        do {
            _ = try await oauth.exchange(code: "c", verifier: "v")
            XCTFail("deveria lançar tokenEndpointError")
        } catch {
            XCTAssertEqual(error as? GoogleOAuthError, .tokenEndpointError("invalid_grant: Malformed auth code."))
        }
    }

    func testTokenEndpointNonJSONErrorFallsBackToInvalidResponse() async {
        let oauth = makeOAuth()
        URLProtocolMock.handler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!
            return (response, Data("erro interno".utf8))
        }
        do {
            _ = try await oauth.exchange(code: "c", verifier: "v")
            XCTFail("deveria lançar invalidTokenResponse")
        } catch {
            XCTAssertEqual(error as? GoogleOAuthError, .invalidTokenResponse)
        }
    }
}
