import XCTest
@testable import Fred

final class AudioDeviceFilterTests: XCTestCase {
    private let devices: [AudioDevice] = [
        AudioDevice(id: 1, name: "MacBook Pro Microphone", isInput: true, isBluetooth: false),
        AudioDevice(id: 2, name: "BlackHole 2ch", isInput: true, isBluetooth: false),
        AudioDevice(id: 3, name: "AirPods Pro", isInput: false, isBluetooth: true),
        AudioDevice(id: 4, name: "Built-in Speakers", isInput: false, isBluetooth: false),
    ]

    func testFiltersInputs() {
        XCTAssertEqual(AudioDeviceFilter.inputs(devices).map(\.id), [1, 2])
    }

    func testDetectsBlackHole() {
        XCTAssertEqual(AudioDeviceFilter.blackHole(in: devices)?.id, 2)
    }

    func testBlackHoleCaseInsensitive() {
        let device = AudioDevice(id: 9, name: "BLACKHOLE 16ch", isInput: true, isBluetooth: false)
        XCTAssertTrue(device.isBlackHole)
        XCTAssertEqual(AudioDeviceFilter.blackHole(in: [device])?.id, 9)
    }

    func testBluetoothWarningLogic() {
        XCTAssertTrue(AudioDeviceFilter.requiresBluetoothWarning(devices: devices, defaultOutputID: 3))
        XCTAssertFalse(AudioDeviceFilter.requiresBluetoothWarning(devices: devices, defaultOutputID: 4))
        XCTAssertFalse(AudioDeviceFilter.requiresBluetoothWarning(devices: devices, defaultOutputID: nil))
        XCTAssertFalse(AudioDeviceFilter.requiresBluetoothWarning(devices: devices, defaultOutputID: 999))
    }
}

final class RunningAppsFilterTests: XCTestCase {
    private let apps: [RunningApp] = [
        RunningApp(bundleID: "com.fred.app", name: "Fred", icon: nil, pid: 1),
        RunningApp(bundleID: "us.zoom.xos", name: "zoom.us", icon: nil, pid: 2),
        RunningApp(bundleID: "com.microsoft.teams", name: "Microsoft Teams", icon: nil, pid: 3),
    ]

    func testExcludesSelf() {
        let result = RunningAppsFilter.excludingSelf(apps, selfBundleID: "com.fred.app")
        XCTAssertEqual(result.count, 2)
        XCTAssertFalse(result.contains { $0.bundleID == "com.fred.app" })
    }

    func testSortedByNameCaseInsensitive() {
        let sorted = RunningAppsFilter.sortedByName(apps)
        XCTAssertEqual(sorted.map(\.name), ["Fred", "Microsoft Teams", "zoom.us"])
    }
}
