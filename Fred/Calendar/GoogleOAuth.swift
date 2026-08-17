import AuthenticationServices
import AppKit
import Foundation

struct GoogleTokens: Codable, Equatable {
    var accessToken: String
    var refreshToken: String?
    var expiresAt: Date?
}

enum GoogleOAuthError: Error, Equatable {
    case noRefreshToken
    case invalidTokenResponse
    case authorizationFailed(String)
}

/// OAuth2 do Google para apps instalados (PKCE + ASWebAuthenticationSession).
/// Tokens persistidos no Keychain. URLSession injetável para testes.
final class GoogleOAuth {
    struct Config {
        var clientID: String
        var clientSecret: String
        var redirectURI: String
        var tokenURL = URL(string: "https://oauth2.googleapis.com/token")!
        var authURL = URL(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        var scopes = ["openid", "email", "https://www.googleapis.com/auth/calendar.events"]
    }

    private let config: Config
    private let session: URLSession
    private let keychain: KeychainStoring
    private let tokensKey = "google.tokens"
    private lazy var presentationProvider = AuthPresentationProvider()

    init(config: Config, session: URLSession = .shared, keychain: KeychainStoring) {
        self.config = config
        self.session = session
        self.keychain = keychain
    }

    // MARK: - Estado

    func storedTokens() -> GoogleTokens? {
        guard let data = try? keychain.get(tokensKey),
              let tokens = try? JSONDecoder().decode(GoogleTokens.self, from: Data(data.utf8)) else { return nil }
        return tokens
    }

    func isSignedIn() -> Bool {
        storedTokens()?.refreshToken != nil
    }

    private func save(_ tokens: GoogleTokens) throws {
        let data = try JSONEncoder().encode(tokens)
        try keychain.set(String(data: data, encoding: .utf8) ?? "", for: tokensKey)
    }

    // MARK: - Fluxo de autorização (UI)

    func startAuthorization() async throws {
        let verifier = PKCE.codeVerifier()
        let challenge = PKCE.codeChallenge(verifier: verifier)
        let state = PKCE.state()

        var components = URLComponents(url: config.authURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: config.clientID),
            URLQueryItem(name: "redirect_uri", value: config.redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: config.scopes.joined(separator: " ")),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "consent"),
        ]
        guard let url = components.url else { throw GoogleOAuthError.authorizationFailed("URL inválida") }
        let callbackScheme = URL(string: config.redirectURI)?.scheme ?? ""

        let code: String = try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: callbackScheme) { callback, error in
                if let error {
                    continuation.resume(throwing: GoogleOAuthError.authorizationFailed(String(describing: error)))
                    return
                }
                guard let callback,
                      let components = URLComponents(url: callback, resolvingAgainstBaseURL: false),
                      let code = components.queryItems?.first(where: { $0.name == "code" })?.value,
                      !code.isEmpty else {
                    continuation.resume(throwing: GoogleOAuthError.authorizationFailed("sem código no callback"))
                    return
                }
                continuation.resume(returning: code)
            }
            session.presentationContextProvider = self.presentationProvider
            session.prefersEphemeralWebBrowserSession = true
            session.start()
        }
        _ = try await exchange(code: code, verifier: verifier)
    }

    // MARK: - Tokens (testável)

    func exchange(code: String, verifier: String) async throws -> GoogleTokens {
        let form = [
            "code": code,
            "client_id": config.clientID,
            "client_secret": config.clientSecret,
            "redirect_uri": config.redirectURI,
            "grant_type": "authorization_code",
            "code_verifier": verifier,
        ]
        let tokens = try await tokenRequest(form: form)
        guard tokens.refreshToken != nil else { throw GoogleOAuthError.noRefreshToken }
        try save(tokens)
        return tokens
    }

    func refreshAccessToken() async throws -> GoogleTokens {
        guard let stored = storedTokens(), let refresh = stored.refreshToken else {
            throw GoogleOAuthError.noRefreshToken
        }
        let form = [
            "client_id": config.clientID,
            "client_secret": config.clientSecret,
            "refresh_token": refresh,
            "grant_type": "refresh_token",
        ]
        let fresh = try await tokenRequest(form: form)
        let merged = GoogleTokens(
            accessToken: fresh.accessToken,
            refreshToken: fresh.refreshToken ?? refresh,
            expiresAt: fresh.expiresAt
        )
        try save(merged)
        return merged
    }

    func accessToken() async throws -> String {
        if let tokens = storedTokens(),
           let expiresAt = tokens.expiresAt,
           expiresAt > Date().addingTimeInterval(60) {
            return tokens.accessToken
        }
        return try await refreshAccessToken().accessToken
    }

    private func tokenRequest(form: [String: String]) async throws -> GoogleTokens {
        var request = URLRequest(url: config.tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var components = URLComponents()
        components.queryItems = form.map { URLQueryItem(name: $0.key, value: $0.value) }
        request.httpBody = components.query?.data(using: .utf8)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw GoogleOAuthError.invalidTokenResponse
        }
        struct TokenDTO: Decodable {
            var access_token: String
            var refresh_token: String?
            var expires_in: Int?
        }
        guard let dto = try? JSONDecoder().decode(TokenDTO.self, from: data) else {
            throw GoogleOAuthError.invalidTokenResponse
        }
        return GoogleTokens(
            accessToken: dto.access_token,
            refreshToken: dto.refresh_token,
            expiresAt: dto.expires_in.map { Date().addingTimeInterval(TimeInterval($0)) }
        )
    }
}

private final class AuthPresentationProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        NSApp.keyWindow ?? NSApp.windows.first ?? ASPresentationAnchor()
    }
}
