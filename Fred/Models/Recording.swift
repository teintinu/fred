import Foundation

/// Origem do áudio de uma gravação.
enum AudioSource: String, Codable, Equatable {
    case microphone
    case appAudio
}

/// Estados do pipeline de processamento de uma gravação.
enum RecordingStatus: String, Codable, Equatable {
    case recorded
    case transcribing
    case transcribed
    case summarized
    case failed
}

/// Metadados de uma gravação.
struct Recording: Identifiable, Codable, Equatable {
    var id: UUID
    var fileName: String
    var source: AudioSource
    var appBundleID: String?
    var appName: String?
    var startDate: Date
    var endDate: Date?
    var durationSeconds: TimeInterval?
    var languageDetected: String?
    var status: RecordingStatus
    var transcript: String?
    var summary: SummaryResult?
    var errorMessage: String?
}

/// Utilidade central de datas ISO-8601 (com timezone).
enum FredISO8601 {
    static let formatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        return f
    }()

    static func date(from string: String) -> Date? {
        formatter.date(from: string)
    }

    static func string(from date: Date) -> String {
        formatter.string(from: date)
    }
}
