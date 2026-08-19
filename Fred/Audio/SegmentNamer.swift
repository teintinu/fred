import Foundation

/// Nomeação de segmentos de áudio e conversões puras — testáveis.
enum SegmentNamer {
    /// `rec.wav` + índice 2 → `rec.seg-002.wav` (mesmo diretório).
    static func segmentURL(for fullURL: URL, index: Int) -> URL {
        let base = fullURL.deletingPathExtension().lastPathComponent
        return fullURL
            .deletingLastPathComponent()
            .appendingPathComponent("\(base).seg-\(String(format: "%03d", index)).wav")
    }

    /// Converte duração em segundos para quantidade de frames (mono).
    static func frames(for seconds: Double, sampleRate: Double) -> Int {
        max(1, Int(seconds * sampleRate))
    }
}
