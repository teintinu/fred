import Foundation

/// Migra segredos antigos do Keychain para o armazenamento atual (arquivo),
/// preservando o que o usuário já configurou em builds anteriores.
enum SecretMigrator {
    static let migrationKeys = [
        "deepseek.apiKey",
        "google.clientID",
        "google.clientSecret",
        "google.redirectURI",
        "google.tokens",
    ]

    /// Copia chaves do `source` para o `destination` apenas quando ainda não existem lá.
    /// Retorna quantos itens foram migrados.
    static func migrate(
        from source: KeychainStoring,
        to destination: KeychainStoring,
        keys: [String] = migrationKeys
    ) -> Int {
        var migrated = 0
        for key in keys {
            // Nunca sobrescreve valor já existente no destino.
            if let existing = try? destination.get(key), !existing.isEmpty {
                continue
            }
            if let value = try? source.get(key), !value.isEmpty {
                try? destination.set(value, for: key)
                migrated += 1
            }
        }
        return migrated
    }
}
