import Foundation

/// Wrapper global dos serviços do Google (OAuth + Calendar), configurado nas Preferências.
@MainActor
final class GoogleOAuthService {
    static var shared: GoogleOAuthService?

    let oauth: GoogleOAuth
    private let keychain: KeychainStoring

    init(oauth: GoogleOAuth, keychain: KeychainStoring) {
        self.oauth = oauth
        self.keychain = keychain
    }

    func isSignedIn() -> Bool {
        oauth.isSignedIn()
    }

    func calendarAPI() -> GoogleCalendarAPI? {
        GoogleCalendarAPI(oauth: oauth)
    }

    /// Lê a configuração do Keychain; retorna nil se incompleta.
    static func configured(from keychain: KeychainStoring) -> GoogleOAuthService? {
        guard let clientID = try? keychain.get("google.clientID"),
              let clientSecret = try? keychain.get("google.clientSecret"),
              !clientID.isEmpty, !clientSecret.isEmpty else { return nil }
        let config = GoogleOAuth.Config(
            clientID: clientID,
            clientSecret: clientSecret,
            redirectURI: (try? keychain.get("google.redirectURI")) ?? "com.fred.app:/oauth2callback"
        )
        return GoogleOAuthService(oauth: GoogleOAuth(config: config, keychain: keychain), keychain: keychain)
    }
}
