import XCTest
@testable import Fred

@MainActor
final class LiveTranscriptionServiceTests: XCTestCase {
    private func makeFakeWhisper(in dir: URL, output: String) throws -> String {
        let scriptPath = dir.appendingPathComponent("fake-whisper.sh")
        let script = """
        #!/bin/bash
        prev=""
        for a in "$@"; do
          if [[ "$prev" == "-of" ]]; then out="$a"; fi
          prev="$a"
        done
        echo "\(output)" > "$out.txt"
        exit 0
        """
        try script.write(to: scriptPath, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptPath.path)
        return scriptPath.path
    }

    private func makeSegment(in dir: URL, name: String) throws -> URL {
        let url = dir.appendingPathComponent(name)
        try Data([0x52, 0x49, 0x46, 0x46]).write(to: url)
        return url
    }

    private func waitUntil(timeout: TimeInterval = 3, _ condition: @escaping () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        return condition()
    }

    func testHiddenPanelSkipsAllProcessing() async throws {
        let dir = try makeTempDir()
        defer { removeTempDir(dir) }
        let binary = try makeFakeWhisper(in: dir, output: "segmento secreto")
        let deepseek = MockDeepseek()

        let service = LiveTranscriptionService(
            dependencies: .init(
                makeTranscriber: { WhisperCLITranscriber(binaryPath: binary, modelPath: binary) },
                deepseek: deepseek
            ),
            summaryDebounce: 0.05
        )
        service.isPanelVisible = false // painel oculto

        service.enqueueSegment(try makeSegment(in: dir, name: "s1.wav"))
        try await Task.sleep(nanoseconds: 250_000_000)

        XCTAssertTrue(service.transcript.isEmpty, "painel invisível não deve transcrever")
        XCTAssertTrue(service.summary.isEmpty, "painel invisível não deve resumir")
        XCTAssertEqual(deepseek.liveSummaryCallCount, 0)
    }

    func testVisiblePanelTranscribesAndSummarizesInPTBR() async throws {
        let dir = try makeTempDir()
        defer { removeTempDir(dir) }
        let binary = try makeFakeWhisper(in: dir, output: "trecho da reunião")
        let deepseek = MockDeepseek(liveSummaryResult: "resumo em português do brasil")

        let service = LiveTranscriptionService(
            dependencies: .init(
                makeTranscriber: { WhisperCLITranscriber(binaryPath: binary, modelPath: binary) },
                deepseek: deepseek
            ),
            summaryEverySegments: 2,
            summaryDebounce: 0.05
        )
        service.isPanelVisible = true

        service.enqueueSegment(try makeSegment(in: dir, name: "s1.wav"))
        service.enqueueSegment(try makeSegment(in: dir, name: "s2.wav"))

        let done = await waitUntil {
            service.transcript.contains("trecho da reunião")
                && service.summary == "resumo em português do brasil"
        }
        XCTAssertTrue(done, "transcript='\(service.transcript)' summary='\(service.summary)'")
        // Dois segmentos concatenados na transcrição original
        XCTAssertEqual(service.transcript.components(separatedBy: "trecho da reunião").count - 1, 2)
        XCTAssertEqual(deepseek.liveSummaryCallCount, 1)
    }

    func testResetClearsState() {
        let service = LiveTranscriptionService(dependencies: .init(deepseek: nil))
        service.isPanelVisible = true
        service.reset()
        XCTAssertTrue(service.transcript.isEmpty)
        XCTAssertTrue(service.summary.isEmpty)
        XCTAssertFalse(service.isProcessing)
    }

    func testFinishRefreshesSummaryWithFullTranscript() async throws {
        let dir = try makeTempDir()
        defer { removeTempDir(dir) }
        let binary = try makeFakeWhisper(in: dir, output: "conversa final")
        let deepseek = MockDeepseek(liveSummaryResult: "resumo final")

        let service = LiveTranscriptionService(
            dependencies: .init(
                makeTranscriber: { WhisperCLITranscriber(binaryPath: binary, modelPath: binary) },
                deepseek: deepseek
            ),
            summaryEverySegments: 99, // nunca dispara por segmentos
            summaryDebounce: 0.05
        )
        service.isPanelVisible = true
        service.enqueueSegment(try makeSegment(in: dir, name: "s1.wav"))

        let transcribed = await waitUntil { service.transcript.contains("conversa final") }
        XCTAssertTrue(transcribed)
        XCTAssertTrue(service.summary.isEmpty, "resumo não deve disparar com every=99")

        service.finish()
        let done = await waitUntil { service.summary == "resumo final" }
        XCTAssertTrue(done)
        XCTAssertEqual(deepseek.liveSummaryCallCount, 1)
    }
}
