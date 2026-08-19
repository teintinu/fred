import SwiftUI

/// Conteúdo do painel ao vivo:
/// - Esquerda: transcrição no idioma ORIGINAL (tempo real).
/// - Direita: resumo SEMPRE em português (tempo real, com debounce).
/// Controles: transparência, tamanho da fonte e ocultar.
struct LivePanelView: View {
    @ObservedObject var liveService: LiveTranscriptionService
    @Binding var opacity: Double
    @Binding var fontSize: Double
    var onHide: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            controlBar
            Divider()
            HSplitView {
                transcriptColumn
                summaryColumn
            }
        }
        .background(.ultraThinMaterial)
        .opacity(opacity) // reforço visual além do alphaValue da janela
    }

    private var controlBar: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(liveService.isProcessing ? Color.green : Color.gray)
                .frame(width: 8, height: 8)
            Text(liveService.isProcessing ? "Transcrevendo…" : "Em espera")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            Text("Transparência").font(.caption2).foregroundStyle(.secondary)
            Slider(value: $opacity, in: 0.2...1.0)
                .frame(width: 80)

            Text("Fonte").font(.caption2).foregroundStyle(.secondary)
            Slider(value: $fontSize, in: 10...22, step: 1)
                .frame(width: 60)

            Button(action: onHide) {
                Image(systemName: "eye.slash")
            }
            .buttonStyle(.borderless)
            .help("Ocultar painel (pausa o processamento em tempo real)")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    private var transcriptColumn: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("Transcrição (original)", systemImage: "waveform")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            ScrollView {
                Text(liveService.transcript.isEmpty ? "Aguardando áudio…" : liveService.transcript)
                    .font(.system(size: fontSize))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(10)
        .frame(minWidth: 220, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var summaryColumn: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("Resumo (PT-BR)", systemImage: "text.alignleft")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            ScrollView {
                Text(liveService.summary.isEmpty ? "O resumo aparece aqui conforme a conversa avança…" : liveService.summary)
                    .font(.system(size: fontSize))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(10)
        .frame(minWidth: 220, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
