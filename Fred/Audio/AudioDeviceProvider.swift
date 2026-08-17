import CoreAudio
import Foundation

/// Descrição simplificada de um dispositivo de áudio.
struct AudioDevice: Equatable, Identifiable {
    let id: UInt32
    let name: String
    let isInput: Bool
    let isBluetooth: Bool

    var isBlackHole: Bool { name.localizedCaseInsensitiveContains("blackhole") }
}

protocol AudioDeviceProviding {
    func devices() -> [AudioDevice]
    func defaultOutputDeviceID() -> UInt32?
}

/// Filtros puros — testáveis sem CoreAudio.
enum AudioDeviceFilter {
    static func inputs(_ devices: [AudioDevice]) -> [AudioDevice] {
        devices.filter(\.isInput)
    }

    static func blackHole(in devices: [AudioDevice]) -> AudioDevice? {
        devices.first(where: \.isBlackHole)
    }

    /// True se o dispositivo de saída padrão for Bluetooth (risco de drift com BlackHole).
    static func requiresBluetoothWarning(devices: [AudioDevice], defaultOutputID: UInt32?) -> Bool {
        guard let id = defaultOutputID,
              let device = devices.first(where: { $0.id == id }) else { return false }
        return device.isBluetooth
    }
}

/// Implementação real via HAL do CoreAudio.
final class CoreAudioDeviceProvider: AudioDeviceProviding {
    func devices() -> [AudioDevice] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        let systemObject = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectGetPropertyDataSize(systemObject, &address, 0, nil, &size) == noErr else { return [] }
        let count = Int(size) / MemoryLayout<AudioDeviceID>.size
        var ids = [AudioDeviceID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(systemObject, &address, 0, nil, &size, &ids) == noErr else { return [] }
        return ids.compactMap { device(id: $0) }
    }

    func defaultOutputDeviceID() -> UInt32? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var id = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let systemObject = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectGetPropertyData(systemObject, &address, 0, nil, &size, &id) == noErr else { return nil }
        return id
    }

    private func device(id: AudioDeviceID) -> AudioDevice? {
        guard let name = stringProperty(id: id, selector: kAudioObjectPropertyName) else { return nil }
        let isInput = streamCount(id: id, scope: kAudioObjectPropertyScopeInput) > 0
        let transport = transportType(id: id)
        return AudioDevice(id: id, name: name, isInput: isInput, isBluetooth: transport == kAudioDeviceTransportTypeBluetooth)
    }

    private func stringProperty(id: AudioDeviceID, selector: AudioObjectPropertySelector) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: CFString?
        var size = UInt32(MemoryLayout<CFString?>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr,
              let value else { return nil }
        return value as String
    }

    private func streamCount(id: AudioDeviceID, scope: AudioObjectPropertyScope) -> Int {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr else { return 0 }
        return Int(size) / MemoryLayout<AudioStreamID>.size
    }

    private func transportType(id: AudioDeviceID) -> UInt32 {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr else { return 0 }
        return value
    }
}
