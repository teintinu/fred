import SwiftUI

@main
struct FredApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(appState: appState)
        } label: {
            Image(systemName: appState.isCapturing ? "waveform" : "waveform.slash")
        }
        .menuBarExtraStyle(.menu)
    }
}
