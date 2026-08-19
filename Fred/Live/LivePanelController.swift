import AppKit
import Combine
import SwiftUI

/// Controlador do painel flutuante ao vivo.
/// Propriedades-chave:
/// - `level = .floating` → fica acima de qualquer outro app.
/// - `collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]` → aparece em todos os
///   Spaces/workspaces, inclusive sobre apps em tela cheia.
/// - `alphaValue` ajustável → transparência.
/// - Redimensionável + fonte ajustável.
@MainActor
final class LivePanelController: NSObject, NSWindowDelegate, ObservableObject {
    @Published var opacity: Double { didSet { applyOpacity(); persist() } }
    @Published var fontSize: Double { didSet { persist() } }
    @Published private(set) var isVisible = false

    let liveService: LiveTranscriptionService
    var onVisibilityChanged: ((Bool) -> Void)?

    private var panel: NSPanel?
    private var hostingView: NSHostingView<LivePanelView>?

    private static let frameAutosaveName = "FredLivePanel"

    init(liveService: LiveTranscriptionService) {
        self.liveService = liveService
        let saved = PanelPreferences()
        self.opacity = PanelPreferences.clampOpacity(saved.opacity)
        self.fontSize = PanelPreferences.clampFontSize(saved.fontSize)
        super.init()
    }

    func toggle() {
        isVisible ? hide() : show()
    }

    func show() {
        if panel == nil { makePanel() }
        guard let panel else { return }
        panel.setFrameUsingName(Self.frameAutosaveName)
        panel.orderFrontRegardless()
        isVisible = true
        liveService.setPanelVisible(true)
        onVisibilityChanged?(true)
        persist()
    }

    func hide() {
        panel?.orderOut(nil)
        isVisible = false
        liveService.setPanelVisible(false)
        onVisibilityChanged?(false)
        persist()
    }

    // MARK: - Construção do painel

    private func makePanel() {
        let saved = PanelPreferences()
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 440),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView, .utilityWindow, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.title = "Fred ao vivo"
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.alphaValue = opacity
        panel.minSize = NSSize(width: 380, height: 240)
        panel.isReleasedWhenClosed = false
        panel.setFrameAutosaveName(Self.frameAutosaveName)
        panel.setFrameUsingName(Self.frameAutosaveName)

        let rootView = LivePanelView(
            liveService: liveService,
            opacity: Binding(
                get: { [weak self] in self?.opacity ?? saved.opacity },
                set: { [weak self] in self?.opacity = PanelPreferences.clampOpacity($0) }
            ),
            fontSize: Binding(
                get: { [weak self] in self?.fontSize ?? saved.fontSize },
                set: { [weak self] in self?.fontSize = PanelPreferences.clampFontSize($0) }
            ),
            onHide: { [weak self] in self?.hide() }
        )
        let hosting = NSHostingView(rootView: rootView)
        hosting.autoresizingMask = [.width, .height]
        panel.contentView = hosting
        panel.delegate = self
        self.panel = panel
        hostingView = hosting
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        isVisible = false
        liveService.setPanelVisible(false)
        onVisibilityChanged?(false)
        persist()
    }

    // MARK: - Persistência

    private func applyOpacity() {
        panel?.alphaValue = opacity
    }

    private func persist() {
        var prefs = PanelPreferences()
        prefs.isVisible = isVisible
        prefs.opacity = opacity
        prefs.fontSize = fontSize
        prefs.save()
    }
}
