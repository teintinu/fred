import SwiftUI

struct MenuBarView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        Button(appState.isCapturing ? "Parar captura" : "Iniciar captura (microfone)") {
            appState.toggleCapture()
        }
        .keyboardShortcut("r", modifiers: .command)

        Menu("Capturar de app…") {
            if appState.runningApps.isEmpty {
                Text("Nenhum app compatível")
            }
            ForEach(appState.runningApps) { app in
                Button(app.name) { appState.startAppCapture(app) }
            }
        }

        Divider()

        Button(appState.panelVisible ? "Ocultar painel ao vivo" : "Mostrar painel ao vivo") {
            appState.togglePanel()
        }
        .keyboardShortcut("l", modifiers: .command)

        if appState.bluetoothWarning {
            Text("⚠️ Saída Bluetooth — use a saída embutida ao gravar")
                .font(.caption)
        }
        switch appState.blackHoleStatus {
        case .missing:
            Text("ℹ️ BlackHole não instalado — capture de apps indisponível")
                .font(.caption)
        case .needsReboot:
            Text("⚠️ BlackHole instalado — reinicie o Mac para ativar")
                .font(.caption)
        case .active:
            EmptyView()
        }

        Divider()

        Button("Abrir histórico…") {
            appState.showHistory()
        }
        .keyboardShortcut("h", modifiers: .command)

        Button("Preferências…") {
            appState.showPreferences()
        }
        .keyboardShortcut(",", modifiers: .command)

        Divider()

        if let error = appState.lastError {
            Text(error).font(.caption).foregroundStyle(.red)
        }

        Button("Sair do Fred") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q", modifiers: .command)
    }
}
