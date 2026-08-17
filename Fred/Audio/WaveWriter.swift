import Foundation

enum WaveWriterError: Error, Equatable {
    case fileNotOpen
}

/// Gravador WAV canônico (PCM 16-bit) com tamanhos finalizados no header.
/// Puro Foundation — testável sem áudio real.
final class WaveWriter {
    private let fileURL: URL
    private var fileHandle: FileHandle?
    let sampleRate: Int
    let channelCount: Int
    private(set) var bytesWritten: UInt32 = 0

    init(fileURL: URL, sampleRate: Int, channelCount: Int) throws {
        self.fileURL = fileURL
        self.sampleRate = sampleRate
        self.channelCount = channelCount
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if !FileManager.default.fileExists(atPath: fileURL.path) {
            FileManager.default.createFile(atPath: fileURL.path, contents: nil)
        }
        let handle = try FileHandle(forWritingTo: fileURL)
        self.fileHandle = handle
        writeHeader(to: handle)
    }

    private func writeHeader(to handle: FileHandle) {
        var header = Data()
        func ascii(_ s: String) { header.append(s.data(using: .ascii)!) }
        func le<T>(_ v: T) {
            var v = v
            withUnsafeBytes(of: &v) { header.append(contentsOf: $0) }
        }
        ascii("RIFF")
        le(UInt32(0)) // tamanho total — finalizado
        ascii("WAVE")
        ascii("fmt ")
        le(UInt32(16))
        le(UInt16(1)) // PCM
        le(UInt16(channelCount))
        le(UInt32(sampleRate))
        le(UInt32(sampleRate * channelCount * 2))
        le(UInt16(channelCount * 2))
        le(UInt16(16)) // bits
        ascii("data")
        le(UInt32(0)) // tamanho dos dados — finalizado
        handle.write(header)
    }

    /// Converte um buffer Float32 (mono ou interleaved) em Int16 e grava.
    func append(floatBuffer: UnsafePointer<Float>, frameCount: Int) throws {
        var samples = [Int16](repeating: 0, count: frameCount)
        for i in 0..<frameCount {
            let s = max(-1.0, min(1.0, Double(floatBuffer[i])))
            samples[i] = Int16(s * 32767.0)
        }
        try append(samples: samples)
    }

    func append(samples: [Int16]) throws {
        guard let handle = fileHandle else { throw WaveWriterError.fileNotOpen }
        samples.withUnsafeBufferPointer { buffer in
            handle.write(Data(buffer: buffer))
        }
        bytesWritten += UInt32(samples.count * MemoryLayout<Int16>.size)
    }

    /// Fecha o arquivo e corrige os tamanhos no header (RIFF e data).
    func finalize() throws {
        guard let handle = fileHandle else { throw WaveWriterError.fileNotOpen }
        var riffSize = UInt32(36) + bytesWritten
        try handle.seek(toOffset: 4)
        handle.write(Data(bytes: &riffSize, count: 4))
        var dataSize = bytesWritten
        try handle.seek(toOffset: 40)
        handle.write(Data(bytes: &dataSize, count: 4))
        try handle.close()
        fileHandle = nil
    }
}
