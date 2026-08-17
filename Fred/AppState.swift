import AppKit
import Combine
import CoreAudio
import Foundation

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
    @Published var blackHoleDetected = false
    @Published var lastError: String?
    @Published var whisperStatus: String = ""
    @Published var googleConnected = false

    // MARK: - Serviços

    let store: RecordingStore
    let draftStore: DraftStore
    let keychain = KeychainStore()
    let capture = AudioCaptureEngine()
    let runningAppsProvider: RunningAppsProviding
    let deviceProvider: AudioDeviceProviding
    let notificationScheduler: NotificationScheduling
    private(set) lazy var pipeline = ProcessingPipeline(dependencies: .init(
        transcriber: WhisperCLITranscriber(),
        deepseek: DeepseekClient(apiKeyProvider: { [keychain] in
            try keychain.get("deepseek.apiKey") ?? ""
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
        GoogleOAuthService.shared = GoogleOAuthService.configured(from: keychain)
        refresh()
    }

    // MARK: - Refresh

    func refresh() {
        recordings = store.all().sorted { $0.startDate > $1.startDate }
        drafts = draftStore.drafts
        refreshRunningApps()
        refreshDevices()
        googleConnected = GoogleOAuthService.shared?.isSignedIn() ?? false
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
        blackHoleDetected = AudioDeviceFilter.blackHole(in: devices) != nil
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

        Task {
            do {
                var deviceID: AudioDeviceID?
                if source == .appAudio {
                    guard let blackHole = AudioDeviceFilter.blackHole(in: deviceProvider.devices()) else {
                        throw AudioCaptureEngine.EngineError.noInputDevice
                    }
                    deviceID = blackHole.id
                }
                try await capture.start(to: url, deviceID: deviceID)
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
