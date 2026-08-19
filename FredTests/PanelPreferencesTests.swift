import XCTest
@testable import Fred

final class PanelPreferencesTests: XCTestCase {
    private func makeDefaults() -> UserDefaults {
        let suite = "fred-panel-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    func testStandardDefaultsWhenEmpty() {
        let defaults = makeDefaults()
        let prefs = PanelPreferences(defaults: defaults)
        XCTAssertEqual(prefs, PanelPreferences.standard)
    }

    func testSaveAndLoadRoundtrip() {
        let defaults = makeDefaults()
        var prefs = PanelPreferences(defaults: defaults)
        prefs.isVisible = true
        prefs.opacity = 0.4
        prefs.fontSize = 18
        prefs.save(to: defaults)

        let loaded = PanelPreferences(defaults: defaults)
        XCTAssertEqual(loaded.isVisible, true)
        XCTAssertEqual(loaded.opacity, 0.4, accuracy: 0.001)
        XCTAssertEqual(loaded.fontSize, 18, accuracy: 0.001)
    }

    func testClamping() {
        XCTAssertEqual(PanelPreferences.clampOpacity(0.01), 0.2)
        XCTAssertEqual(PanelPreferences.clampOpacity(5.0), 1.0)
        XCTAssertEqual(PanelPreferences.clampOpacity(0.5), 0.5)
        XCTAssertEqual(PanelPreferences.clampFontSize(5), 10)
        XCTAssertEqual(PanelPreferences.clampFontSize(99), 22)
    }
}
