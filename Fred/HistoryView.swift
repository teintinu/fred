import SwiftUI

struct HistoryView: View {
    @ObservedObject var appState: AppState
    @State private var selection: Recording.ID?

    var body: some View {
        NavigationSplitView {
            List(appState.recordings, selection: $selection) { recording in
                VStack(alignment: .leading, spacing: 2) {
                    Text(recording.source == .microphone ? "🎙 Microfone" : "📱 \(recording.appName ?? "App")")
                        .font(.headline)
                    HStack(spacing: 4) {
                        Text(recording.startDate, style: .date)
                        Text(recording.startDate, style: .time)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    Text(statusLabel(recording.status))
                        .font(.caption)
                        .foregroundStyle(statusColor(recording.status))
                }
                .tag(recording.id)
            }
        } detail: {
            if let recording = appState.recordings.first(where: { $0.id == selection }) {
                RecordingDetailView(appState: appState, recording: recording)
            } else {
                Text("Selecione uma gravação")
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear { appState.refresh() }
    }

    private func statusLabel(_ status: RecordingStatus) -> String {
        switch status {
        case .recorded: return "Gravado"
        case .transcribing: return "Transcrevendo…"
        case .transcribed: return "Transcrito"
        case .summarized: return "Resumido ✓"
        case .failed: return "Falhou ✖"
        }
    }

    private func statusColor(_ status: RecordingStatus) -> Color {
        switch status {
        case .summarized: return .green
        case .failed: return .red
        case .transcribing: return .orange
        default: return .secondary
        }
    }
}

struct RecordingDetailView: View {
    @ObservedObject var appState: AppState
    let recording: Recording

    private var drafts: [EventDraft] {
        appState.drafts.filter { $0.recordingID == recording.id }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let error = recording.errorMessage {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                }
                if let transcript = recording.transcript, !transcript.isEmpty {
                    section("Transcrição") {
                        Text(transcript).textSelection(.enabled)
                    }
                }
                if let summary = recording.summary {
                    section("Resumo") {
                        Text(summary.summary).textSelection(.enabled)
                    }
                    if !summary.keyPoints.isEmpty {
                        section("Pontos-chave") { bulletList(summary.keyPoints) }
                    }
                    if !summary.decisions.isEmpty {
                        section("Decisões") { bulletList(summary.decisions) }
                    }
                    if !summary.nextSteps.isEmpty {
                        section("Próximos passos") { bulletList(summary.nextSteps) }
                    }
                    if !summary.followUps.isEmpty {
                        section("Follow-ups") { bulletList(summary.followUps.map(\.text)) }
                    }
                }
                if !drafts.isEmpty {
                    section("Eventos sugeridos") {
                        ForEach(drafts) { draft in
                            DraftRow(appState: appState, draft: draft)
                        }
                    }
                }
            }
            .padding()
        }
        .navigationTitle(recording.source == .microphone ? "Microfone" : (recording.appName ?? "Gravação"))
    }

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
    }

    private func bulletList(_ items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(items, id: \.self) { item in
                HStack(alignment: .top, spacing: 6) {
                    Text("•")
                    Text(item).textSelection(.enabled)
                }
            }
        }
    }
}

struct DraftRow: View {
    @ObservedObject var appState: AppState
    let draft: EventDraft

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(draft.title).font(.subheadline.bold())
            Text("\(draft.startDate.formatted()) → \(draft.endDate.formatted()) (\(draft.timeZone))")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                switch draft.status {
                case .proposed:
                    Button("Confirmar") { appState.confirmDraft(draft.id) }
                    Button("Rejeitar", role: .destructive) { appState.rejectDraft(draft.id) }
                case .confirmed:
                    Button("Criar no Google Agenda") {
                        Task { await appState.createConfirmedDraftInCalendar(draft.id) }
                    }
                    .disabled(!appState.googleConnected)
                    if !appState.googleConnected {
                        Text("Conecte o Google nas Preferências").font(.caption).foregroundStyle(.orange)
                    }
                case .created:
                    Label("Criado no Google Calendar", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                case .rejected:
                    Text("Rejeitado").foregroundStyle(.secondary)
                }
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
    }
}
