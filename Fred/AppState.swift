import AppKit
import Combine
import CoreAudio
import Foundation
import SwiftUI

/// Estado global do app — orquestra captura, pipeline, apps e preferências.
@MainActor
final class AppState: ObservableObject {
    // MARK: - Publicados

    @Published var isCapturing = false
    @Published var recordings: [Recording] = []
    @Published var drafts: [EventDraft] = []
    @Published var runningApps: [RunningApp] = []
    @Published var selectedAppBundleID: String?
    @Published var bluetoothWarning = false
    @Published var blackHoleStatus: BlackHoleStatus = .missing
    @Published var lastError: String?
    @Published var whisperStatus: String = ""
    @Published var googleConnected = false
    @Published var panelVisible = false
    @Published var deepseekConfigured = false
    @Published var deepseekTestResult: String?
    @Published var calendarTestResult: String?

    // MARK: - Serviços

    let store: RecordingStore
    let draftStore: DraftStore
    let secrets = FileSecretsStore()
    let capture = AudioCaptureEngine()
    let runningAppsProvider: RunningAppsProviding
    let deviceProvider: AudioDeviceProviding
    let notificationScheduler: NotificationScheduling
    let liveService: LiveTranscriptionService
    let panelController: LivePanelController
    private(set) lazy var historyWindowController = FredWindowController(
        title: "Histórico",
        contentSize: NSSize(width: 780, height: 540)
    ) { [weak self] in
        guard let self else { return AnyView(EmptyView()) }
        return AnyView(HistoryView(appState: self))
    }
    private(set) lazy var preferencesWindowController = FredWindowController(
        title: "Preferências",
        contentSize: NSSize(width: 520, height: 580)
    ) { [weak self] in
        guard let self else { return AnyView(EmptyView()) }
        return AnyView(PreferencesView(appState: self))
    }
    private(set) lazy var pipeline = ProcessingPipeline(dependencies: .init(
        transcriber: WhisperCLITranscriber(),
        deepseek: DeepseekClient(apiKeyProvider: { [secrets] in
            try secrets.get("deepseek.apiKey") ?? ""
        }),
        store: store,
        drafts: draftStore
    ))
    private var currentRecordingID: UUID?

    static var appSupportRoot: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Fred", isDirectory: true)
    }

    init(
        runningAppsProvider: RunningAppsProviding = WorkspaceRunningApps(),
        deviceProvider: AudioDeviceProviding = CoreAudioDeviceProvider(),
        notificationScheduler: NotificationScheduling = UNNotificationScheduler()
    ) {
        let root = Self.appSupportRoot
        self.store = RecordingStore(root: root)
        self.draftStore = DraftStore(url: root.appendingPathComponent("drafts.json"))
        self.runningAppsProvider = runningAppsProvider
        self.deviceProvider = deviceProvider
        self.notificationScheduler = notificationScheduler
        self.selectedAppBundleID = UserDefaults.standard.string(forKey: "fred.selectedAppBundleID")
        // Recupera segredos salvos no Keychain por builds anteriores (chave Deepseek etc.).
        let migrated = SecretMigrator.migrate(from: KeychainStore(), to: secrets)
        FredLogger.log("AppState.init: migrados=\(migrated) clientID=\((try? secrets.get("google.clientID")) != nil) tokens=\((try? secrets.get("google.tokens")) != nil) deepseek=\((try? secrets.get("deepseek.apiKey")) != nil)")
        self.liveService = LiveTranscriptionService(dependencies: .init(
            deepseek: DeepseekClient(apiKeyProvider: { [secrets] in
                try secrets.get("deepseek.apiKey") ?? ""
            })
        ))
        self.panelController = LivePanelController(liveService: liveService)
        GoogleOAuthService.shared = GoogleOAuthService.configured(from: secrets)
        panelController.onVisibilityChanged = { [weak self] visible in
            self?.panelVisible = visible
        }
        refresh()
        // Reabrir o painel DEPOIS do bootstrap: abrir janelas/NSWindow durante a
        // inicialização do SwiftUI dispara "setting value during update" e aborta o app.
        Task { @MainActor in
            if PanelPreferences().isVisible {
                panelController.show()
            }
        }
    }

    // MARK: - Refresh

    func refresh() {
        recordings = store.all().sorted { $0.startDate > $1.startDate }
        drafts = draftStore.drafts
        refreshRunningApps()
        refreshDevices()
        googleConnected = GoogleOAuthService.shared?.isSignedIn() ?? false
        deepseekConfigured = !((try? secrets.get("deepseek.apiKey"))?.isEmpty ?? true)
    }

    func refreshRunningApps() {
        runningApps = RunningAppsFilter.sortedByName(
            RunningAppsFilter.excludingSelf(
                runningAppsProvider.runningApps(),
                selfBundleID: Bundle.main.bundleIdentifier
            )
        )
    }

    func refreshDevices() {
        let devices = deviceProvider.devices()
        blackHoleStatus = AudioDeviceFilter.blackHoleStatus(devices: devices)
        bluetoothWarning = AudioDeviceFilter.requiresBluetoothWarning(
            devices: devices,
            defaultOutputID: deviceProvider.defaultOutputDeviceID()
        )
    }

    // MARK: - Captura

    func startMicrophoneCapture() {
        startCapture(app: nil)
    }

    func startAppCapture(_ app: RunningApp) {
        selectedAppBundleID = app.bundleID
        UserDefaults.standard.set(app.bundleID, forKey: "fred.selectedAppBundleID")
        refreshRunningApps()
        startCapture(app: app)
    }

    private func startCapture(app: RunningApp?) {
        guard !isCapturing else { return }
        let source: AudioSource = app == nil ? .microphone : .appAudio
        let url = store.nextRecordingURL()
        var recording = Recording(
            id: UUID(),
            fileName: url.lastPathComponent,
            source: source,
            appBundleID: app?.bundleID,
            appName: app?.name,
            startDate: Date(),
            endDate: nil,
            durationSeconds: nil,
            languageDetected: nil,
            status: .recorded,
            transcript: nil,
            summary: nil,
            errorMessage: nil
        )
        store.add(recording)
        refresh()
        liveService.reset()

        Task {
            do {
                var deviceID: AudioDeviceID?
                if source == .appAudio {
                    guard let blackHole = AudioDeviceFilter.blackHole(in: deviceProvider.devices()) else {
                        throw AudioCaptureEngine.EngineError.noInputDevice
                    }
                    deviceID = blackHole.id
                }
                // Painel invisível → sem processamento em tempo real (zero custo de CPU/API).
                let onSegment: ((URL, Int) -> Void)? = panelVisible
                    ? { [weak liveService] url, _ in
                        Task { @MainActor in liveService?.enqueueSegment(url) }
                    }
                    : nil
                try await capture.start(to: url, deviceID: deviceID, segmentSeconds: 12, onSegment: onSegment)
                currentRecordingID = recording.id
                isCapturing = true
            } catch {
                recording.status = .failed
                recording.errorMessage = "Falha ao iniciar captura: \(error)"
                store.update(recording)
                lastError = recording.errorMessage
                refresh()
            }
        }
    }

    func stopCapture() {
        guard isCapturing else { return }
        do {
            try capture.stop()
        } catch {
            lastError = "Falha ao finalizar gravação: \(error)"
        }
        isCapturing = false
        liveService.finish()
        if let id = currentRecordingID, var recording = store.recording(withID: id) {
            recording.endDate = Date()
            recording.durationSeconds = Date().timeIntervalSince(recording.startDate)
            store.update(recording)
            currentRecordingID = nil
            Task { await pipeline.process(id) }
        }
        refresh()
    }

    func toggleCapture() {
        isCapturing ? stopCapture() : startMicrophoneCapture()
    }

    /// Mostra/oculta o painel ao vivo (flutuante, todos os Spaces, transparência ajustável).
    func togglePanel() {
        panelController.toggle()
    }

    /// Abre a janela de histórico (controller manual — confiável em apps LSUIElement).
    func showHistory() {
        historyWindowController.show()
    }

    /// Abre a janela de preferências (controller manual).
    func showPreferences() {
        preferencesWindowController.show()
    }

    // MARK: - Rascunhos / calendário

    func confirmDraft(_ id: UUID) {
        draftStore.confirm(id)
        refresh()
    }

    func rejectDraft(_ id: UUID) {
        draftStore.reject(id)
        refresh()
    }

    func createConfirmedDraftInCalendar(_ id: UUID) async {
        guard let draft = draftStore.draft(id: id),
              let calendar = GoogleOAuthService.shared?.calendarAPI() else {
            lastError = "Google Calendar não configurado."
            return
        }
        do {
            let googleEventID = try await calendar.createEvent(draft)
            draftStore.markCreated(id: id, googleEventID: googleEventID)
            if let created = draftStore.draft(id: id),
               let plan = NotificationPlanner.planEventReminder(draft: created) {
                try? await notificationScheduler.schedule(plan)
            }
        } catch {
            lastError = "Falha ao criar evento: \(error)"
        }
        refresh()
    }

    // MARK: - Utilidades

    /// Testa a chave do Deepseek com uma chamada mínima (ping) à API.
    func testDeepseek() async {
        deepseekTestResult = nil
        let client = DeepseekClient(apiKeyProvider: { [secrets] in
            try secrets.get("deepseek.apiKey") ?? ""
        })
        do {
            let reply = try await client.ping()
            deepseekTestResult = "✅ OK — resposta da API: \(reply)"
        } catch {
            deepseekTestResult = "❌ Falha: \(error)"
        }
    }

    /// Testa a conexão com o Google Calendar listando os próximos eventos.
    func testCalendarConnection() async {
        calendarTestResult = nil
        guard let calendar = GoogleOAuthService.shared?.calendarAPI() else {
            calendarTestResult = "❌ Google Calendar não configurado."
            return
        }
        do {
            let events = try await calendar.listUpcomingEvents(maxResults: 5)
            if events.isEmpty {
                calendarTestResult = "✅ Conectado — sem eventos próximos."
            } else {
                let lines = events.prefix(5).map { event in
                    let title = event.summary ?? "(sem título)"
                    return "• \(title) — \(event.start ?? "")"
                }.joined(separator: "\n")
                calendarTestResult = "✅ Conectado — próximos eventos:\n\(lines)"
            }
        } catch {
            calendarTestResult = "❌ Falha: \(error)"
        }
    }

    func checkWhisper() {
        let binary = ProcessInfo.processInfo.environment["WHISPER_CLI_PATH"] ?? "/opt/homebrew/bin/whisper-cli"
        let model = ProcessInfo.processInfo.environment["FRED_WHISPER_MODEL"] ?? WhisperCLITranscriber.defaultModelPath()
        var parts: [String] = []
        parts.append(FileManager.default.isExecutableFile(atPath: binary) ? "whisper-cli: OK" : "whisper-cli: não encontrado (brew install whisper-cpp)")
        parts.append(FileManager.default.fileExists(atPath: model) ? "modelo: OK" : "modelo: ausente (scripts/download-whisper-model.sh)")
        whisperStatus = parts.joined(separator: " • ")
    }

    func retentionDays() -> Int {
        UserDefaults.standard.integer(forKey: "fred.retentionDays")
    }

    func setRetentionDays(_ days: Int) {
        UserDefaults.standard.set(days, forKey: "fred.retentionDays")
        store.enforceRetention(days: days)
        refresh()
    }
}
