import Foundation

/// Transcrição e resumo EM TEMPO REAL para o painel ao vivo.
/// Regra de custo: se o painel estiver invisível, segmentos são ignorados
/// (nenhuma chamada ao whisper/Deepseek é feita).
@MainActor
final class LiveTranscriptionService: ObservableObject {
    struct Dependencies {
        var makeTranscriber: () -> Transcriber = { WhisperCLITranscriber() }
        var deepseek: DeepseekProviding?
    }

    @Published private(set) var transcript: String = "" // idioma original
    @Published private(set) var summary: String = "" // sempre PT-BR
    @Published private(set) var isProcessing = false
    @Published var isPanelVisible = false

    private let deps: Dependencies
    private let summaryEverySegments: Int
    private let summaryDebounce: TimeInterval
    private var segmentsProcessed = 0
    private var chainTail: Task<Void, Never>?
    private var summaryTask: Task<Void, Never>?

    init(
        dependencies: Dependencies = .init(),
        summaryEverySegments: Int = 2,
        summaryDebounce: TimeInterval = 8
    ) {
        self.deps = dependencies
        self.summaryEverySegments = max(1, summaryEverySegments)
        self.summaryDebounce = summaryDebounce
    }

    func setPanelVisible(_ visible: Bool) {
        isPanelVisible = visible
    }

    func reset() {
        chainTail?.cancel()
        summaryTask?.cancel()
        chainTail = nil
        summaryTask = nil
        transcript = ""
        summary = ""
        segmentsProcessed = 0
        isProcessing = false
    }

    /// Enfileira um segmento de áudio. Ignorado quando o painel está invisível.
    func enqueueSegment(_ url: URL) {
        guard isPanelVisible else { return }
        let previous = chainTail
        chainTail = Task { [weak self] in
            await previous?.value
            await self?.processSegment(url)
        }
    }

    private func processSegment(_ url: URL) async {
        guard isPanelVisible, !Task.isCancelled else { return }
        isProcessing = true
        defer { isProcessing = false }
        do {
            let result = try await deps.makeTranscriber().transcribe(fileURL: url)
            let text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty, isPanelVisible else { return }
            transcript = transcript.isEmpty ? text : transcript + "\n" + text
            segmentsProcessed += 1
            scheduleSummaryRefreshIfNeeded()
        } catch {
            // Falha silenciosa no painel — o pipeline final trata erros de verdade.
        }
    }

    private func scheduleSummaryRefreshIfNeeded() {
        guard deps.deepseek != nil,
              segmentsProcessed % summaryEverySegments == 0,
              summaryTask == nil else { return }
        summaryTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: UInt64(self.summaryDebounce * 1_000_000_000))
            guard !Task.isCancelled,
                  self.isPanelVisible,
                  let deepseek = self.deps.deepseek else {
                self.summaryTask = nil
                return
            }
            let text = String(self.transcript.suffix(6000))
            if let updated = try? await deepseek.liveSummary(transcript: text) {
                self.summary = updated
            }
            self.summaryTask = nil
        }
    }

    /// Chamado ao parar a captura: dispara o resumo final com a transcrição completa.
    func finish() {
        guard isPanelVisible, !transcript.isEmpty, let deepseek = deps.deepseek else { return }
        Task { [weak self] in
            guard let self else { return }
            if let updated = try? await deepseek.liveSummary(transcript: self.transcript) {
                self.summary = updated
            }
        }
    }
}
