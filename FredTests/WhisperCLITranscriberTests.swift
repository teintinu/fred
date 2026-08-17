import XCTest
@testable import Fred

final class WhisperCLITranscriberTests: XCTestCase {
    func testBinaryNotFoundThrows() async {
        let transcriber = WhisperCLITranscriber(
            binaryPath: "/nonexistent/whisper-cli",
            modelPath: "/nonexistent/model.bin"
        )
        do {
            _ = try await transcriber.transcribe(fileURL: URL(fileURLWithPath: "/tmp/x.wav"))
            XCTFail("deveria lançar binaryNotFound")
        } catch {
            XCTAssertEqual(error as? TranscriptionError, .binaryNotFound)
        }
    }

    func testModelNotFoundThrows() async {
        // /bin/echo existe e é executável — mas o modelo não.
        let transcriber = WhisperCLITranscriber(binaryPath: "/bin/echo", modelPath: "/nonexistent/model.bin")
        do {
            _ = try await transcriber.transcribe(fileURL: URL(fileURLWithPath: "/tmp/x.wav"))
            XCTFail("deveria lançar modelNotFound")
        } catch {
            XCTAssertEqual(error as? TranscriptionError, .modelNotFound)
        }
    }

    func testFakeBinaryProducesTranscription() async throws {
        let dir = try makeTempDir()
        defer { removeTempDir(dir) }

        // Binário fake que imita a CLI do whisper: escreve <prefixo>.txt
        let scriptPath = dir.appendingPathComponent("fake-whisper.sh")
        let script = """
        #!/bin/bash
        prev=""
        for a in "$@"; do
          if [[ "$prev" == "-of" ]]; then out="$a"; fi
          prev="$a"
        done
        echo "ola mundo transcrito" > "$out.txt"
        exit 0
        """
        try script.write(to: scriptPath, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptPath.path)

        let wav = dir.appendingPathComponent("input.wav")
        try Data([0x52, 0x49, 0x46, 0x46]).write(to: wav)

        let transcriber = WhisperCLITranscriber(binaryPath: scriptPath.path, modelPath: wav.path)
        let result = try await transcriber.transcribe(fileURL: wav)
        XCTAssertEqual(result.text, "ola mundo transcrito")
        XCTAssertEqual(result.language, "auto")
    }

    func testFakeBinaryEmptyOutputThrows() async throws {
        let dir = try makeTempDir()
        defer { removeTempDir(dir) }

        let scriptPath = dir.appendingPathComponent("fake-empty.sh")
        let script = """
        #!/bin/bash
        prev=""
        for a in "$@"; do
          if [[ "$prev" == "-of" ]]; then out="$a"; fi
          prev="$a"
        done
        echo -n "" > "$out.txt"
        exit 0
        """
        try script.write(to: scriptPath, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptPath.path)

        let wav = dir.appendingPathComponent("input.wav")
        try Data([0x52, 0x49, 0x46, 0x46]).write(to: wav)

        let transcriber = WhisperCLITranscriber(binaryPath: scriptPath.path, modelPath: wav.path)
        do {
            _ = try await transcriber.transcribe(fileURL: wav)
            XCTFail("deveria lançar emptyOutput")
        } catch {
            XCTAssertEqual(error as? TranscriptionError, .emptyOutput)
        }
    }
}
