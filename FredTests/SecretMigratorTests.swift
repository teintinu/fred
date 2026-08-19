import XCTest
@testable import Fred

final class SecretMigratorTests: XCTestCase {
    func testMigratesMissingKeys() {
        let source = MockKeychain()
        let destination = MockKeychain()
        try? source.set("chave-deepseek", for: "deepseek.apiKey")
        try? source.set("token-google", for: "google.tokens")

        let migrated = SecretMigrator.migrate(from: source, to: destination)

        XCTAssertEqual(migrated, 2)
        XCTAssertEqual(try? destination.get("deepseek.apiKey"), "chave-deepseek")
        XCTAssertEqual(try? destination.get("google.tokens"), "token-google")
    }

    func testNeverOverwritesExistingDestination() {
        let source = MockKeychain()
        let destination = MockKeychain()
        try? source.set("chave-nova", for: "deepseek.apiKey")
        try? destination.set("chave-ja-salva", for: "deepseek.apiKey")

        let migrated = SecretMigrator.migrate(from: source, to: destination)

        XCTAssertEqual(migrated, 0)
        XCTAssertEqual(try? destination.get("deepseek.apiKey"), "chave-ja-salva")
    }

    func testIgnoresEmptyValues() {
        let source = MockKeychain()
        let destination = MockKeychain()
        try? source.set("", for: "deepseek.apiKey")

        XCTAssertEqual(SecretMigrator.migrate(from: source, to: destination), 0)
        XCTAssertNil(try? destination.get("deepseek.apiKey"))
    }

    func testMigratesOnlyListedKeys() {
        let source = MockKeychain()
        let destination = MockKeychain()
        try? source.set("valor", for: "chave.fora.da.lista")

        XCTAssertEqual(SecretMigrator.migrate(from: source, to: destination), 0)
        XCTAssertNil(try? destination.get("chave.fora.da.lista"))
    }
}
