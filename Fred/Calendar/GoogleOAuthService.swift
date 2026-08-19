import Foundation

/// Wrapper global dos serviços do Google (OAuth + Calendar), configurado nas Preferências.
/// Fluxo automático: só precisa do Client ID (PKCE dispensa o secret); a URL de login
/// é aberta no navegador pelo próprio botão de conectar.
final class GoogleOAuthService {
    static var shared: GoogleOAuthService?

    let oauth: GoogleOAuth

    init(oauth: GoogleOAuth) {
        self.oauth = oauth
    }

    func isSignedIn() -> Bool {
        oauth.isSignedIn()
    }

    func calendarAPI() -> GoogleCalendarAPI {
        GoogleCalendarAPI(oauth: oauth)
    }

    /// Resolve o Client ID: Keychain primeiro, depois a variável de ambiente
    /// `FRED_GOOGLE_CLIENT_ID` (dev sem digitação manual).
    static func resolveClientID(
        keychain: KeychainStoring,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> String? {
        if let stored = try? keychain.get("google.clientID"),
           !stored.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return stored
        }
        if let env = environment["FRED_GOOGLE_CLIENT_ID"],
           !env.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return env
        }
        return nil
    }

    static func redirectURI(keychain: KeychainStoring) -> String {
        (try? keychain.get("google.redirectURI")) ?? "http://127.0.0.1:5173"
    }

    /// Heurística para reconhecer um Client ID do Google (p/ auto-preenchimento do clipboard).
    static func looksLikeClientID(_ candidate: String) -> Bool {
        let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        return trimmed.contains(".apps.googleusercontent.com")
    }

    /// Salva credenciais: Client ID sempre; Client Secret opcional (removido quando vazio).
    static func saveCredentials(clientID: String, clientSecret: String?, keychain: KeychainStoring) {
        try? keychain.set(clientID, for: "google.clientID")
        if let secret = clientSecret, !secret.isEmpty {
            try? keychain.set(secret, for: "google.clientSecret")
        } else {
            try? keychain.delete("google.clientSecret")
        }
    }

    /// Monta o serviço a partir da configuração disponível; nil se não houver Client ID.
    static func configured(from keychain: KeychainStoring) -> GoogleOAuthService? {
        guard let clientID = resolveClientID(keychain: keychain),
              !clientID.isEmpty else { return nil }
        let config = GoogleOAuth.Config(
            clientID: clientID,
            clientSecret: (try? keychain.get("google.clientSecret")) ?? nil,
            redirectURI: redirectURI(keychain: keychain)
        )
        return GoogleOAuthService(oauth: GoogleOAuth(config: config, keychain: keychain))
    }
}
