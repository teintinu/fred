import Foundation

/// Preferências do painel ao vivo — persistidas em UserDefaults.
/// Testável com `UserDefaults(suiteName:)`.
struct PanelPreferences: Equatable {
    var isVisible: Bool
    var opacity: Double
    var fontSize: Double

    static let standard = PanelPreferences(isVisible: false, opacity: 0.85, fontSize: 13)

    init(isVisible: Bool, opacity: Double, fontSize: Double) {
        self.isVisible = isVisible
        self.opacity = opacity
        self.fontSize = fontSize
    }

    init(defaults: UserDefaults = .standard) {
        isVisible = defaults.object(forKey: "fred.panel.isVisible") as? Bool ?? Self.standard.isVisible
        opacity = defaults.object(forKey: "fred.panel.opacity") as? Double ?? Self.standard.opacity
        fontSize = defaults.object(forKey: "fred.panel.fontSize") as? Double ?? Self.standard.fontSize
    }

    func save(to defaults: UserDefaults = .standard) {
        defaults.set(isVisible, forKey: "fred.panel.isVisible")
        defaults.set(opacity, forKey: "fred.panel.opacity")
        defaults.set(fontSize, forKey: "fred.panel.fontSize")
    }

    static func clampOpacity(_ value: Double) -> Double { max(0.2, min(1.0, value)) }
    static func clampFontSize(_ value: Double) -> Double { max(10, min(22, value)) }
}
