import Foundation

/// Estado global do app (Fase 1: placeholder — captura real chega na Fase 2).
@MainActor
final class AppState: ObservableObject {
    @Published var isCapturing = false
}
