import SwiftUI

struct PreferencesView: View {
    @ObservedObject var appState: AppState
    @State private var deepseekKey = ""
    @State private var googleClientID = ""
    @State private var googleClientSecret = ""
    @State private var retentionDays = 30

    var body: some View {
        Form {
            Section("Deepseek") {
                SecureField("API Key", text: $deepseekKey)
                Button("Salvar chave Deepseek") {
                    try? appState.keychain.set(deepseekKey, for: "deepseek.apiKey")
                }
            }

            Section("Google Calendar") {
                TextField("Client ID", text: $googleClientID)
                SecureField("Client Secret", text: $googleClientSecret)
                Text("Redirect URI no Google Cloud Console: com.fred.app:/oauth2callback")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button(appState.googleConnected ? "Conectado ✓ (reconectar)" : "Conectar ao Google Calendar") {
                    saveGoogleAndConnect()
                }
            }

            Section("Retenção") {
                Stepper("Manter gravações por \(retentionDays) dias", value: $retentionDays, in: 7...3650)
                    .onChange(of: retentionDays) { newValue in
                        appState.setRetentionDays(newValue)
                    }
            }

            Section("Transcrição (whisper.cpp)") {
                Text(appState.whisperStatus.isEmpty ? "Verifique a instalação" : appState.whisperStatus)
                    .font(.caption)
                Button("Verificar instalação") { appState.checkWhisper() }
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(width: 480)
        .onAppear(perform: load)
    }

    private func load() {
        deepseekKey = (try? appState.keychain.get("deepseek.apiKey")) ?? ""
        googleClientID = (try? appState.keychain.get("google.clientID")) ?? ""
        googleClientSecret = (try? appState.keychain.get("google.clientSecret")) ?? ""
        retentionDays = appState.retentionDays()
        appState.checkWhisper()
    }

    private func saveGoogleAndConnect() {
        try? appState.keychain.set(googleClientID, for: "google.clientID")
        try? appState.keychain.set(googleClientSecret, for: "google.clientSecret")
        GoogleOAuthService.shared = GoogleOAuthService.configured(from: appState.keychain)
        Task { @MainActor in
            do {
                try await GoogleOAuthService.shared?.oauth.startAuthorization()
                appState.refresh()
            } catch {
                appState.lastError = "Falha na autorização do Google: \(error)"
            }
        }
    }
}
