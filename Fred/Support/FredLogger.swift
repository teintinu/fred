import Foundation

/// Log simples em arquivo para diagnóstico do fluxo OAuth/API.
/// Arquivo: ~/Library/Application Support/Fred/fred.log
enum FredLogger {
    static let queue = DispatchQueue(label: "com.fred.logger")

    /// Override para testes.
    static var logURLOverride: URL?

    static var logURL: URL {
        if let logURLOverride { return logURLOverride }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Fred/fred.log")
    }

    static func log(_ message: String) {
        let formatter = ISO8601DateFormatter()
        let line = "\(formatter.string(from: Date())) \(message)\n"
        queue.async {
            let url = logURL
            try? FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            if let handle = try? FileHandle(forWritingTo: url) {
                try? handle.seekToEnd()
                try? handle.write(contentsOf: Data(line.utf8))
                try? handle.close()
            } else {
                try? Data(line.utf8).write(to: url, options: .atomic)
            }
        }
    }
}
