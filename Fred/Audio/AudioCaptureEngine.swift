import AVFoundation
import AudioToolbox
import CoreAudio
import Foundation

/// Captura de áudio via AVAudioEngine (microfone padrão ou dispositivo de entrada específico,
/// ex.: BlackHole). Serialização em WAV 16 kHz mono 16-bit.
@MainActor
final class AudioCaptureEngine: ObservableObject {
    enum EngineError: Error, Equatable {
        case noInputDevice
    }

    @Published private(set) var isCapturing = false
    private let engine = AVAudioEngine()
    private var writer: WaveWriter?

    static func requestMicrophonePermission() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .audio)
        default:
            return false
        }
    }

    /// Inicia a captura. `deviceID` nil = dispositivo de entrada padrão (microfone).
    func start(to url: URL, sampleRate: Double = 16_000, deviceID: AudioDeviceID? = nil) async throws {
        guard !isCapturing else { return }
        let granted = await Self.requestMicrophonePermission()
        guard granted else { throw EngineError.noInputDevice }

        let input = engine.inputNode
        if let deviceID {
            var mutableID = deviceID
            let status = AudioUnitSetProperty(
                input.audioUnit!,
                kAudioOutputUnitProperty_CurrentDevice,
                kAudioUnitScope_Global,
                0,
                &mutableID,
                UInt32(MemoryLayout<AudioDeviceID>.size)
            )
            guard status == noErr else { throw EngineError.noInputDevice }
        }

        guard let recordFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: 1,
            interleaved: false
        ) else { throw EngineError.noInputDevice }

        writer = try WaveWriter(fileURL: url, sampleRate: Int(sampleRate), channelCount: 1)

        input.installTap(onBus: 0, bufferSize: 2048, format: recordFormat) { [weak self] buffer, _ in
            guard let self, let channelData = buffer.floatChannelData else { return }
            Task { @MainActor in
                try? self.writer?.append(floatBuffer: channelData[0], frameCount: Int(buffer.frameLength))
            }
        }
        try engine.start()
        isCapturing = true
    }

    func stop() throws {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        try writer?.finalize()
        writer = nil
        isCapturing = false
    }
}
