import AppKit
import SwiftUI

struct PreferencesView: View {
    @ObservedObject var appState: AppState
    @State private var deepseekKey = ""
    @State private var retentionDays = 30

    var body: some View {
        Form {
            Section("Deepseek") {
                HStack {
                    SecureField("API Key", text: $deepseekKey)
                    Button("Colar") {
                        if let text = NSPasteboard.general.string(forType: .string) {
                            deepseekKey = text.trimmingCharacters(in: .whitespacesAndNewlines)
                        }
                    }
                    .help("Cola a API Key da área de transferência")
                }
                HStack {
                    Label(
                        appState.deepseekConfigured ? "Configurado ✓" : "Não configurado",
                        systemImage: appState.deepseekConfigured ? "checkmark.circle.fill" : "xmark.circle"
                    )
                    .foregroundStyle(appState.deepseekConfigured ? Color.green : Color.orange)
                    Button("Salvar chave") {
                        try? appState.secrets.set(deepseekKey, for: "deepseek.apiKey")
                        appState.refresh()
                    }
                    Button("Testar conexão") {
                        Task { await appState.testDeepseek() }
                    }
                }
                if let result = appState.deepseekTestResult {
                    Text(result)
                        .font(.caption)
                        .textSelection(.enabled)
                }
            }

            Section("Google Calendar") {
                HStack {
                    Button(appState.googleConnected ? "Reconectar ao Google Calendar" : "Conectar ao Google Calendar") {
                        connectGoogle()
                    }
                    Label(
                        appState.googleConnected ? "Conectado ✓" : "Não conectado",
                        systemImage: appState.googleConnected ? "checkmark.circle.fill" : "xmark.circle"
                    )
                    .foregroundStyle(appState.googleConnected ? Color.green : Color.orange)
                    Button("Editar credenciais…") {
                        editGoogleCredentials()
                    }
                    .controlSize(.small)
                }
                Button("Testar conexão (próximos eventos)") {
                    Task { await appState.testCalendarConnection() }
                }
                .disabled(!appState.googleConnected)
                if let result = appState.calendarTestResult {
                    Text(result)
                        .font(.caption)
                        .textSelection(.enabled)
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
        .frame(width: 500)
        .onAppear(perform: load)
    }

    private func load() {
        deepseekKey = (try? appState.secrets.get("deepseek.apiKey")) ?? ""
        retentionDays = appState.retentionDays()
        appState.checkWhisper()
    }

    /// Fluxo simples: conectado → reautorização direta no navegador;
    /// não conectado → abre SEMPRE o diálogo de credenciais.
    private func connectGoogle() {
        if appState.googleConnected {
            startGoogleOAuth()
        } else {
            editGoogleCredentials()
        }
    }

    /// Diálogo com Client ID e Client Secret (opcional — exigido por clientes tipo "Web").
    private func editGoogleCredentials() {
        let alert = NSAlert()
        alert.messageText = "Credenciais do Google"
        alert.informativeText = """
        Client ID do Google — crie em console.cloud.google.com/apis/credentials.
        O tipo "App de desktop" não precisa de secret. Se o Google devolver
        o erro "client_secret is missing", cole também o Client Secret.
        """

        let idInput = NSTextField(frame: NSRect(x: 0, y: 30, width: 340, height: 24))
        idInput.placeholderString = "Client ID (…apps.googleusercontent.com)"
        let secretInput = NSTextField(frame: NSRect(x: 0, y: 0, width: 340, height: 24))
        secretInput.placeholderString = "Client Secret (opcional)"
        let stack = NSStackView(frame: NSRect(x: 0, y: 0, width: 340, height: 60))
        stack.orientation = .vertical
        stack.spacing = 6
        stack.addArrangedSubview(idInput)
        stack.addArrangedSubview(secretInput)
        alert.accessoryView = stack

        idInput.stringValue = GoogleOAuthService.resolveClientID(keychain: appState.secrets) ?? ""
        // Auto-preenche com um Client ID copiado recentemente (novo ou diferente do salvo).
        if let clipboard = NSPasteboard.general.string(forType: .string),
           GoogleOAuthService.looksLikeClientID(clipboard) {
            let pasted = clipboard.trimmingCharacters(in: .whitespacesAndNewlines)
            if pasted != idInput.stringValue {
                idInput.stringValue = pasted
            }
        }
        secretInput.stringValue = (try? appState.secrets.get("google.clientSecret")) ?? ""

        alert.addButton(withTitle: "Conectar")
        alert.addButton(withTitle: "Abrir console do Google")
        alert.addButton(withTitle: "Cancelar")

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            let clientID = idInput.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            let clientSecret = secretInput.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !clientID.isEmpty else {
                appState.lastError = "Client ID vazio — conexão cancelada."
                return
            }
            GoogleOAuthService.saveCredentials(
                clientID: clientID,
                clientSecret: clientSecret.isEmpty ? nil : clientSecret,
                keychain: appState.secrets
            )
            GoogleOAuthService.shared = GoogleOAuthService.configured(from: appState.secrets)
            startGoogleOAuth()
        case .alertSecondButtonReturn:
            if let url = URL(string: "https://console.cloud.google.com/apis/credentials") {
                NSWorkspace.shared.open(url)
            }
        default:
            break
        }
    }

    private func startGoogleOAuth() {
        guard GoogleOAuthService.shared != nil else {
            appState.lastError = "Não foi possível configurar o Google (Client ID ausente)."
            return
        }
        // Abre a URL de login no navegador e autoriza automaticamente (PKCE + loopback).
        Task { @MainActor in
            do {
                try await GoogleOAuthService.shared?.oauth.startAuthorization()
                appState.refresh()
            } catch {
                let message = "Falha na autorização do Google: \(error)"
                appState.lastError = message
                let alert = NSAlert()
                alert.messageText = "Não foi possível conectar ao Google"
                var info = message
                if message.contains("client_secret") {
                    info += """


                    Seu Client ID foi criado como "Aplicativo da Web", que EXIGE o Client Secret.
                    Clique na engrenagem ⚙️ ao lado do botão Conectar e cole também o Client Secret
                    (ou crie um cliente do tipo "App de desktop", que dispensa o secret).
                    """
                }
                alert.informativeText = info
                alert.addButton(withTitle: "OK")
                alert.runModal()
            }
        }
    }
}
