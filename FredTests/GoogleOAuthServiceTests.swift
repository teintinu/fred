import XCTest
@testable import Fred

final class GoogleOAuthServiceTests: XCTestCase {
    func testResolveClientIDPrefersKeychainOverEnvironment() {
        let keychain = MockKeychain()
        try? keychain.set("kc-id", for: "google.clientID")
        let resolved = GoogleOAuthService.resolveClientID(
            keychain: keychain,
            environment: ["FRED_GOOGLE_CLIENT_ID": "env-id"]
        )
        XCTAssertEqual(resolved, "kc-id")
    }

    func testResolveClientIDFallsBackToEnvironment() {
        let keychain = MockKeychain()
        let resolved = GoogleOAuthService.resolveClientID(
            keychain: keychain,
            environment: ["FRED_GOOGLE_CLIENT_ID": "env-id"]
        )
        XCTAssertEqual(resolved, "env-id")
    }

    func testResolveClientIDIgnoresBlankValues() {
        let keychain = MockKeychain()
        try? keychain.set("   ", for: "google.clientID")
        let resolved = GoogleOAuthService.resolveClientID(
            keychain: keychain,
            environment: ["FRED_GOOGLE_CLIENT_ID": ""]
        )
        XCTAssertNil(resolved)
    }

    func testResolveClientIDNilWithoutAnySource() {
        XCTAssertNil(GoogleOAuthService.resolveClientID(keychain: MockKeychain(), environment: [:]))
    }

    func testConfiguredReturnsNilWithoutClientID() {
        XCTAssertNil(GoogleOAuthService.configured(from: MockKeychain()))
    }

    func testConfiguredBuildsServiceWithClientIDOnly() {
        let keychain = MockKeychain()
        try? keychain.set("kc-id", for: "google.clientID")
        let service = GoogleOAuthService.configured(from: keychain)
        XCTAssertNotNil(service)
        XCTAssertFalse(service?.isSignedIn() == true)
    }

    func testLooksLikeClientID() {
        XCTAssertTrue(GoogleOAuthService.looksLikeClientID("123456789-abc.apps.googleusercontent.com"))
        XCTAssertTrue(GoogleOAuthService.looksLikeClientID(" 456-xyz.apps.googleusercontent.com "))
        XCTAssertFalse(GoogleOAuthService.looksLikeClientID(""))
        XCTAssertFalse(GoogleOAuthService.looksLikeClientID("texto qualquer"))
        XCTAssertFalse(GoogleOAuthService.looksLikeClientID("   "))
    }

    func testSaveCredentialsKeepsIDAndSecret() {
        let keychain = MockKeychain()
        GoogleOAuthService.saveCredentials(clientID: "cid", clientSecret: "secret", keychain: keychain)
        XCTAssertEqual(try? keychain.get("google.clientID"), "cid")
        XCTAssertEqual(try? keychain.get("google.clientSecret"), "secret")
    }

    func testSaveCredentialsRemovesSecretWhenEmpty() {
        let keychain = MockKeychain()
        try? keychain.set("secret-antigo", for: "google.clientSecret")
        GoogleOAuthService.saveCredentials(clientID: "cid", clientSecret: nil, keychain: keychain)
        XCTAssertNil(try? keychain.get("google.clientSecret"))
        GoogleOAuthService.saveCredentials(clientID: "cid", clientSecret: "", keychain: keychain)
        XCTAssertNil(try? keychain.get("google.clientSecret"))
    }
}
