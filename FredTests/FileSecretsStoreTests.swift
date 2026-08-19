import XCTest
@testable import Fred

final class FileSecretsStoreTests: XCTestCase {
    func testSetGetOverwriteDeleteRoundtrip() throws {
        let dir = try makeTempDir()
        defer { removeTempDir(dir) }
        let store = FileSecretsStore(fileURL: dir.appendingPathComponent("secrets.json"))

        XCTAssertNil(try store.get("chave1"))
        try store.set("valor1", for: "chave1")
        XCTAssertEqual(try store.get("chave1"), "valor1")

        try store.set("valor2", for: "chave1")
        XCTAssertEqual(try store.get("chave1"), "valor2")

        try store.delete("chave1")
        XCTAssertNil(try store.get("chave1"))
    }

    func testPersistsAcrossInstances() throws {
        let dir = try makeTempDir()
        defer { removeTempDir(dir) }
        let url = dir.appendingPathComponent("secrets.json")

        try FileSecretsStore(fileURL: url).set("segredo", for: "k")
        XCTAssertEqual(try FileSecretsStore(fileURL: url).get("k"), "segredo")
    }

    func testFilePermissionsAreOwnerOnly() throws {
        let dir = try makeTempDir()
        defer { removeTempDir(dir) }
        let url = dir.appendingPathComponent("secrets.json")

        try FileSecretsStore(fileURL: url).set("x", for: "k")

        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let permissions = attributes[.posixPermissions] as? Int
        XCTAssertEqual(permissions, 0o600, "segredos legíveis apenas pelo dono")
    }

    func testMissingFileReturnsNil() throws {
        let dir = try makeTempDir()
        defer { removeTempDir(dir) }
        let store = FileSecretsStore(fileURL: dir.appendingPathComponent("nao-existe.json"))
        XCTAssertNil(try store.get("qualquer"))
    }
}
