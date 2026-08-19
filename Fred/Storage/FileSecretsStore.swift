import Foundation

/// Armazenamento de segredos em arquivo local com permissão 0600 (só o dono lê).
/// Alternativa ao Keychain para builds de desenvolvimento: com assinatura ad-hoc,
/// cada rebuild vira "outro app" para o Keychain e o macOS pede senha a cada acesso.
/// Mesmo protocolo (`KeychainStoring`) — trocar de volta para Keychain é trivial.
final class FileSecretsStore: KeychainStoring {
    let fileURL: URL
    private let queue = DispatchQueue(label: "com.fred.filesecrets")

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Fred/secrets.json")
    }

    private func load() -> [String: String] {
        guard let data = try? Data(contentsOf: fileURL),
              let dict = try? JSONDecoder().decode([String: String].self, from: data) else {
            return [:]
        }
        return dict
    }

    private func save(_ dict: [String: String]) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(dict) else { return }
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? data.write(to: fileURL, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }

    func set(_ value: String, for key: String) throws {
        queue.sync {
            var dict = load()
            dict[key] = value
            save(dict)
        }
    }

    func get(_ key: String) throws -> String? {
        queue.sync { load()[key] }
    }

    func delete(_ key: String) throws {
        queue.sync {
            var dict = load()
            dict.removeValue(forKey: key)
            save(dict)
        }
    }
}
