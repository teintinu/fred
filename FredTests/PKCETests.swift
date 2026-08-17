import CryptoKit
import XCTest
@testable import Fred

final class PKCETests: XCTestCase {
    func testVerifierHasExpectedLengthAndCharset() {
        let verifier = PKCE.codeVerifier()
        // 64 bytes aleatórios → 86 caracteres base64url; RFC 7636 exige 43...128.
        XCTAssertTrue((43...128).contains(verifier.count), "verificador tem \(verifier.count) caracteres")
        let allowed = CharacterSet(charactersIn: PKCE.allowedCharacters)
        XCTAssertTrue(verifier.unicodeScalars.allSatisfy { allowed.contains($0) })
    }

    func testVerifierIsRandom() {
        let a = PKCE.codeVerifier()
        let b = PKCE.codeVerifier()
        XCTAssertNotEqual(a, b)
    }

    func testChallengeMatchesSHA256Base64URL() {
        let verifier = "test-verifier-123"
        let challenge = PKCE.codeChallenge(verifier: verifier)

        let digest = SHA256.hash(data: Data(verifier.utf8))
        let expected = Data(digest).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        XCTAssertEqual(challenge, expected)
        XCTAssertEqual(challenge.count, 43) // SHA-256 = 32 bytes → 43 chars base64url
    }

    func testStateIsNonEmptyUUID() {
        XCTAssertNotNil(UUID(uuidString: PKCE.state()))
    }
}
