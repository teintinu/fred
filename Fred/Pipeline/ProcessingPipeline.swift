import Foundation

/// Orquestra o pipeline: transcrição → resumo (chat) → ações (reasoner) → rascunhos.
/// Regra de segurança: o pipeline NUNCA confirma ou cria eventos — só gera rascunhos `.proposed`.
@MainActor
final class ProcessingPipeline: ObservableObject {
    struct Dependencies {
        var transcriber: Transcriber
        var deepseek: DeepseekProviding
        var store: RecordingStore
        var drafts: DraftStore
    }

    private let deps: Dependencies
    @Published private(set) var isProcessing = false

    init(dependencies: Dependencies) {
        self.deps = dependencies
    }

    func process(_ recordingID: UUID) async {
        guard var recording = deps.store.recording(withID: recordingID),
              recording.status != .summarized else { return }
        isProcessing = true
        defer { isProcessing = false }

        do {
            // 1) Transcrição
            recording.status = .transcribing
            deps.store.update(recording)
            let fileURL = deps.store.fileURL(for: recording)
            let transcription = try await deps.transcriber.transcribe(fileURL: fileURL)
            recording.transcript = transcription.text
            recording.languageDetected = transcription.language
            recording.status = .transcribed
            deps.store.update(recording)

            // 2) Resumo + ações
            let summary = try await deps.deepseek.summarize(transcript: transcription.text)
            let actions = try await deps.deepseek.extractActions(transcript: transcription.text)
            recording.summary = SummaryResult(
                summary: summary.summary,
                keyPoints: summary.keyPoints,
                decisions: summary.decisions,
                nextSteps: summary.nextSteps,
                proposedEvents: actions.events,
                followUps: actions.followUps
            )
            recording.status = .summarized
            deps.store.update(recording)

            // 3) Rascunhos — sempre `.proposed`, aguardando confirmação manual
            for event in actions.events {
                if let draft = EventDraft.from(proposed: event, recordingID: recording.id) {
                    deps.drafts.add(draft)
                }
            }
        } catch {
            recording.status = .failed
            recording.errorMessage = String(describing: error)
            deps.store.update(recording)
        }
    }
}
