import AppKit
import SwiftUI

/// Abre janelas de forma confiável a partir do menu bar em apps LSUIElement
/// (o `openWindow` do SwiftUI não ativa a janela nesses apps).
@MainActor
final class FredWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private let title: String
    private let contentSize: NSSize
    private let contentProvider: () -> AnyView

    init(title: String, contentSize: NSSize, contentProvider: @escaping () -> AnyView) {
        self.title = title
        self.contentSize = contentSize
        self.contentProvider = contentProvider
        super.init()
    }

    func show() {
        if window == nil {
            let window = NSWindow(
                contentRect: NSRect(origin: .zero, size: contentSize),
                styleMask: [.titled, .closable, .resizable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            window.title = title
            window.isReleasedWhenClosed = false
            window.center()
            window.contentView = NSHostingView(rootView: contentProvider())
            window.delegate = self
            self.window = window
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
