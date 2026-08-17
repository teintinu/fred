import XCTest
@testable import Fred

@MainActor
final class ProcessingPipelineTests: XCTestCase {
    private func makeRecording(in store: RecordingStore) throws -> Recording {
        let url = store.nextRecordingURL()
        try Data("áudio fake".utf8).write(to: url)
        let recording = Recording.fixture(fileName: url.lastPathComponent)
        store.add(recording)
        return recording
    }

    func testHappyPathTranscribesSummarizesAndCreatesProposedDraftsOnly() async throws {
        let root = try makeTempDir()
        defer { removeTempDir(root) }
        let store = RecordingStore(root: root)
        let draftStore = DraftStore(url: root.appendingPathComponent("drafts.json"))
        let recording = try makeRecording(in: store)

        let transcriber = MockTranscriber(result: TranscriptionResult(text: "vamos marcar uma reunião amanhã", language: "auto"))
        let deepseek = MockDeepseek(events: [ProposedEvent.fixture()])
        let pipeline = ProcessingPipeline(dependencies: .init(
            transcriber: transcriber,
            deepseek: deepseek,
            store: store,
            drafts: draftStore
        ))

        await pipeline.process(recording.id)

        let updated = store.recording(withID: recording.id)
        XCTAssertEqual(updated?.status, .summarized)
        XCTAssertEqual(updated?.transcript, "vamos marcar uma reunião amanhã")
        XCTAssertEqual(updated?.languageDetected, "auto")
        XCTAssertNotNil(updated?.summary)

        // Segurança: rascunhos ficam .proposed — NUNCA confirmados/criados automaticamente
        XCTAssertEqual(draftStore.drafts.count, 1)
        XCTAssertEqual(draftStore.drafts.first?.status, .proposed)
        XCTAssertEqual(draftStore.drafts.first?.recordingID, recording.id)
        XCTAssertNil(draftStore.drafts.first?.googleEventID)

        XCTAssertEqual(deepseek.summarizeCallCount, 1)
        XCTAssertEqual(deepseek.extractCallCount, 1)
    }

    func testDeepseekFailureMarksRecordingFailed() async throws {
        let root = try makeTempDir()
        defer { removeTempDir(root) }
        let store = RecordingStore(root: root)
        let draftStore = DraftStore(url: root.appendingPathComponent("drafts.json"))
        let recording = try makeRecording(in: store)

        let transcriber = MockTranscriber(result: TranscriptionResult(text: "oi", language: "auto"))
        let deepseek = MockDeepseek(error: .missingAPIKey)
        let pipeline = ProcessingPipeline(dependencies: .init(
            transcriber: transcriber,
            deepseek: deepseek,
            store: store,
            drafts: draftStore
        ))

        await pipeline.process(recording.id)

        let updated = store.recording(withID: recording.id)
        XCTAssertEqual(updated?.status, .failed)
        XCTAssertEqual(updated?.transcript, "oi")
        XCTAssertNotNil(updated?.errorMessage)
        XCTAssertTrue(draftStore.drafts.isEmpty)
    }

    func testTranscriptionFailureMarksRecordingFailed() async throws {
        let root = try makeTempDir()
        defer { removeTempDir(root) }
        let store = RecordingStore(root: root)
        let draftStore = DraftStore(url: root.appendingPathComponent("drafts.json"))
        let recording = try makeRecording(in: store)

        let transcriber = MockTranscriber(
            result: TranscriptionResult(text: "", language: ""),
            error: .modelNotFound
        )
        let deepseek = MockDeepseek()
        let pipeline = ProcessingPipeline(dependencies: .init(
            transcriber: transcriber,
            deepseek: deepseek,
            store: store,
            drafts: draftStore
        ))

        await pipeline.process(recording.id)

        let updated = store.recording(withID: recording.id)
        XCTAssertEqual(updated?.status, .failed)
        XCTAssertNil(updated?.transcript)
        XCTAssertEqual(deepseek.summarizeCallCount, 0, "Deepseek não deve ser chamado se a transcrição falhar")
    }
}
