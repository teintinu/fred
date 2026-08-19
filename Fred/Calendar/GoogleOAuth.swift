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
    /// Erro retornado pelo endpoint de token (ex.: invalid_grant, redirect_uri_mismatch).
    case tokenEndpointError(String)
    case authorizationFailed(String)
}

/// OAuth2 do Google para apps instalados (Desktop): PKCE + loopback HTTP.
/// O login abre no NAVEGADOR padrão e o callback volta por http://127.0.0.1:<porta>
/// (sem scheme custom, sem domínio próprio — nada de com.fred.app).
final class GoogleOAuth {
    struct Config {
        var clientID: String
        /// Opcional: apps instalados com PKCE não precisam de secret.
        var clientSecret: String? = nil
        var redirectURI: String = "http://127.0.0.1:5173"
        var tokenURL = URL(string: "https://oauth2.googleapis.com/token")!
        var authURL = URL(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        var scopes = ["openid", "email", "https://www.googleapis.com/auth/calendar.events"]
    }

    private let config: Config
    private let session: URLSession
    private let keychain: KeychainStoring
    private let tokensKey = "google.tokens"

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

    // MARK: - Fluxo de autorização (navegador + loopback)

    func startAuthorization() async throws {
        let verifier = PKCE.codeVerifier()
        let challenge = PKCE.codeChallenge(verifier: verifier)
        let state = PKCE.state()
        let port = LoopbackAuthServer.randomPort()
        let redirect = "http://127.0.0.1:\(port)"
        let authURL = try authorizationURL(redirectURI: redirect, challenge: challenge, state: state)

        FredLogger.log("startAuthorization: abrindo navegador com \(authURL.absoluteString.replacingOccurrences(of: "%20", with: " "))")

        let server = LoopbackAuthServer(port: port)
        let (code, returnedState) = try await server.awaitCode(timeout: 120) {
            NSWorkspace.shared.open(authURL)
        }
        FredLogger.log("startAuthorization: callback recebido, stateOK=\(returnedState == state)")
        guard returnedState == state else {
            FredLogger.log("startAuthorization: FALHOU — state divergente")
            throw GoogleOAuthError.authorizationFailed("Estado do callback não confere")
        }
        do {
            let tokens = try await exchange(code: code, verifier: verifier, redirectURI: redirect)
            FredLogger.log("startAuthorization: exchange OK, refreshToken=\(tokens.refreshToken != nil)")
        } catch {
            FredLogger.log("startAuthorization: exchange FALHOU — \(error)")
            throw error
        }
    }

    /// Monta a URL de login (testável).
    func authorizationURL(redirectURI: String, challenge: String, state: String) throws -> URL {
        var components = URLComponents(url: config.authURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: config.clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: config.scopes.joined(separator: " ")),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "consent"),
        ]
        guard let url = components.url else {
            throw GoogleOAuthError.authorizationFailed("URL de autorização inválida")
        }
        return url
    }

    // MARK: - Tokens (testável)

    func exchange(code: String, verifier: String, redirectURI: String? = nil) async throws -> GoogleTokens {
        var form = [
            "code": code,
            "client_id": config.clientID,
            "redirect_uri": redirectURI ?? config.redirectURI,
            "grant_type": "authorization_code",
            "code_verifier": verifier,
        ]
        if let secret = config.clientSecret, !secret.isEmpty {
            form["client_secret"] = secret
        }
        let tokens = try await tokenRequest(form: form)
        guard tokens.refreshToken != nil else { throw GoogleOAuthError.noRefreshToken }
        try save(tokens)
        return tokens
    }

    func refreshAccessToken() async throws -> GoogleTokens {
        guard let stored = storedTokens(), let refresh = stored.refreshToken else {
            throw GoogleOAuthError.noRefreshToken
        }
        var form = [
            "client_id": config.clientID,
            "refresh_token": refresh,
            "grant_type": "refresh_token",
        ]
        if let secret = config.clientSecret, !secret.isEmpty {
            form["client_secret"] = secret
        }
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
        FredLogger.log("accessToken: cache expirado/ausente — refresh")
        return try await refreshAccessToken().accessToken
    }

    private func tokenRequest(form: [String: String]) async throws -> GoogleTokens {
        var request = URLRequest(url: config.tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var components = URLComponents()
        components.queryItems = form.map { URLQueryItem(name: $0.key, value: $0.value) }
        request.httpBody = components.query?.data(using: .utf8)

        FredLogger.log("tokenRequest: \(form.keys.sorted().joined(separator: ",")) → \(config.tokenURL.absoluteString)")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            FredLogger.log("tokenRequest: HTTP \((response as? HTTPURLResponse)?.statusCode ?? -1) body=\(String(data: data, encoding: .utf8) ?? "")")
            // Tenta extrair o erro detalhado que o Google envia no corpo.
            struct TokenErrorDTO: Decodable {
                var error: String?
                var error_description: String?
            }
            if let dto = try? JSONDecoder().decode(TokenErrorDTO.self, from: data) {
                let detail = [dto.error, dto.error_description]
                    .compactMap { $0 }
                    .joined(separator: ": ")
                if !detail.isEmpty { throw GoogleOAuthError.tokenEndpointError(detail) }
            }
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
