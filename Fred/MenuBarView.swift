import SwiftUI

struct MenuBarView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        Button(appState.isCapturing ? "Parar captura" : "Iniciar captura") {
            appState.isCapturing.toggle()
        }
        .keyboardShortcut("r", modifiers: .command)

        Divider()

        Button("Abrir histórico…") {
            // Fase 2: janela de histórico de gravações
        }

        Button("Preferências…") {
            // Fase 2: janela de preferências
        }

        Divider()

        Button("Sair do Fred") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q", modifiers: .command)
    }
}
