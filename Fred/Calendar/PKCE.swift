import CryptoKit
import Foundation

/// PKCE (RFC 7636) — funções puras, testáveis.
enum PKCE {
    static let allowedCharacters = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"

    static func codeVerifier(length: Int = 64) -> String {
        var bytes = [UInt8](repeating: 0, count: length)
        let status = SecRandomCopyBytes(kSecRandomDefault, length, &bytes)
        if status != errSecSuccess {
            // fallback determinístico apenas para ambientes sem SecRandom (nunca usado em prod)
            var generator = SystemRandomNumberGenerator()
            for i in 0..<length { bytes[i] = UInt8.random(in: 0...255, using: &generator) }
        }
        return Data(bytes).base64URLEncodedString()
    }

    static func codeChallenge(verifier: String) -> String {
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return Data(digest).base64URLEncodedString()
    }

    static func state() -> String {
        UUID().uuidString
    }
}

extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
