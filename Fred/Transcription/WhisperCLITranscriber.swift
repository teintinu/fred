import Foundation

struct TranscriptionResult: Equatable {
    var text: String
    var language: String
}

enum TranscriptionError: Error, Equatable {
    case binaryNotFound
    case modelNotFound
    case processFailed(code: Int32, stderr: String)
    case emptyOutput
}

protocol Transcriber {
    func transcribe(fileURL: URL) async throws -> TranscriptionResult
}

/// Transcreve com o binário `whisper-cli` (whisper.cpp) local.
/// WhisperKit (Swift/Core ML) pode substituí-lo atrás deste mesmo protocolo.
final class WhisperCLITranscriber: Transcriber {
    private let binaryPath: String
    private let modelPath: String

    init(
        binaryPath: String = ProcessInfo.processInfo.environment["WHISPER_CLI_PATH"] ?? "/opt/homebrew/bin/whisper-cli",
        modelPath: String = ProcessInfo.processInfo.environment["FRED_WHISPER_MODEL"] ?? ""
    ) {
        self.binaryPath = binaryPath
        self.modelPath = modelPath
    }

    static func defaultModelPath() -> String {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("Fred/models/ggml-base.bin").path
    }

    func transcribe(fileURL: URL) async throws -> TranscriptionResult {
        guard FileManager.default.isExecutableFile(atPath: binaryPath) else {
            throw TranscriptionError.binaryNotFound
        }
        let model = modelPath.isEmpty ? Self.defaultModelPath() : modelPath
        guard FileManager.default.fileExists(atPath: model) else {
            throw TranscriptionError.modelNotFound
        }
        let prefix = fileURL.deletingPathExtension().path
        let result = try await runProcess([
            "-m", model,
            "-f", fileURL.path,
            "-l", "auto",
            "-otxt",
            "-of", prefix,
        ])
        guard result.terminationStatus == 0 else {
            throw TranscriptionError.processFailed(code: result.terminationStatus, stderr: result.stderr)
        }
        let txtURL = URL(fileURLWithPath: prefix + ".txt")
        guard let text = try? String(contentsOf: txtURL, encoding: .utf8) else {
            throw TranscriptionError.emptyOutput
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw TranscriptionError.emptyOutput }
        return TranscriptionResult(text: trimmed, language: "auto")
    }

    private func runProcess(_ arguments: [String]) async throws -> (terminationStatus: Int32, stderr: String) {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: binaryPath)
            process.arguments = arguments
            let pipe = Pipe()
            process.standardError = pipe
            process.terminationHandler = { p in
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let stderr = String(data: data, encoding: .utf8) ?? ""
                continuation.resume(returning: (p.terminationStatus, stderr))
            }
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: TranscriptionError.processFailed(code: -1, stderr: String(describing: error)))
            }
        }
    }
}
