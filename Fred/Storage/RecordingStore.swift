import Foundation

enum RecordingStoreError: Error, Equatable {
    case notFound
}

/// Armazenamento local de gravações: manifest JSON + arquivos WAV em disco.
/// Thread-safe (fila serial). Testável com diretório temporário.
final class RecordingStore {
    let root: URL
    private(set) var recordings: [Recording] = []
    private let queue = DispatchQueue(label: "com.fred.recordingstore")

    var recordingsDir: URL { root.appendingPathComponent("recordings", isDirectory: true) }
    private var manifestURL: URL { root.appendingPathComponent("recordings.json") }

    init(root: URL) {
        self.root = root
        try? FileManager.default.createDirectory(at: recordingsDir, withIntermediateDirectories: true)
        load()
    }

    private func load() {
        guard let data = try? Data(contentsOf: manifestURL),
              let decoded = try? JSONDecoder.fred.decode([Recording].self, from: data) else {
            recordings = []
            return
        }
        recordings = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder.fred.encode(recordings) else { return }
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try? data.write(to: manifestURL, options: .atomic)
    }

    func all() -> [Recording] {
        queue.sync { recordings }
    }

    func recording(withID id: UUID) -> Recording? {
        queue.sync { recordings.first { $0.id == id } }
    }

    func add(_ recording: Recording) {
        queue.sync {
            recordings.append(recording)
            save()
        }
    }

    func update(_ recording: Recording) {
        queue.sync {
            guard let index = recordings.firstIndex(where: { $0.id == recording.id }) else { return }
            recordings[index] = recording
            save()
        }
    }

    func delete(id: UUID) {
        queue.sync {
            guard let index = recordings.firstIndex(where: { $0.id == id }) else { return }
            let rec = recordings[index]
            try? FileManager.default.removeItem(at: fileURL(for: rec))
            recordings.remove(at: index)
            save()
        }
    }

    func fileURL(for recording: Recording) -> URL {
        recordingsDir.appendingPathComponent(recording.fileName)
    }

    func nextRecordingURL() -> URL {
        recordingsDir.appendingPathComponent("rec-\(UUID().uuidString).wav")
    }

    /// Remove gravações mais antigas que `days` dias. Retorna quantas foram removidas.
    @discardableResult
    func enforceRetention(days: Int) -> Int {
        queue.sync {
            let cutoff = Date().addingTimeInterval(-TimeInterval(days) * 86_400)
            let expired = recordings.filter { $0.startDate < cutoff }
            for rec in expired {
                try? FileManager.default.removeItem(at: fileURL(for: rec))
            }
            recordings.removeAll { $0.startDate < cutoff }
            save()
            return expired.count
        }
    }
}

extension JSONEncoder {
    static let fred: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()
}

extension JSONDecoder {
    static let fred: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
