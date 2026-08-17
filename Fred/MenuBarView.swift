import SwiftUI

struct MenuBarView: View {
    @ObservedObject var appState: AppState
    @Environment(\.openWindow) private var openWindow

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

        if appState.bluetoothWarning {
            Text("⚠️ Saída Bluetooth — use a saída embutida ao gravar")
                .font(.caption)
        }
        if !appState.blackHoleDetected {
            Text("ℹ️ BlackHole não detectado — instale para capturar apps")
                .font(.caption)
        }

        Divider()

        Button("Abrir histórico…") {
            openWindow(id: "history")
        }
        .keyboardShortcut("h", modifiers: .command)

        Button("Preferências…") {
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
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
