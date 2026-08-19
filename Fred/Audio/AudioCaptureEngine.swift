import AVFoundation
import AudioToolbox
import CoreAudio
import Foundation

/// Captura de áudio via AVAudioEngine (microfone padrão ou dispositivo de entrada específico,
/// ex.: BlackHole). Serialização em WAV 16 kHz mono 16-bit.
///
/// Modo tempo real: além do arquivo completo, grava segmentos de ~`segmentSeconds` e
/// notifica `onSegment` (usado pelo painel ao vivo). O callback roda numa fila serial
/// dedicada (nunca na thread de áudio).
@MainActor
final class AudioCaptureEngine: ObservableObject {
    enum EngineError: Error, Equatable {
        case noInputDevice
    }

    @Published private(set) var isCapturing = false
    private let engine = AVAudioEngine()
    private let sampleQueue = DispatchQueue(label: "com.fred.audio.samples")

    private var fullWriter: WaveWriter?
    private var segmentWriter: WaveWriter?
    private var segmentIndex = 0
    private var framesInSegment = 0
    private var framesPerSegment = 0
    private var onSegment: ((URL, Int) -> Void)?
    private var fullURL: URL?
    private var segmentSampleRate = 16_000.0

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
    /// `onSegment` habilita a gravação de segmentos para processamento em tempo real.
    func start(
        to url: URL,
        sampleRate: Double = 16_000,
        deviceID: AudioDeviceID? = nil,
        segmentSeconds: Double = 12,
        onSegment: ((URL, Int) -> Void)? = nil
    ) async throws {
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

        fullURL = url
        segmentSampleRate = sampleRate
        framesPerSegment = SegmentNamer.frames(for: segmentSeconds, sampleRate: sampleRate)
        framesInSegment = 0
        segmentIndex = 0
        self.onSegment = onSegment
        fullWriter = try WaveWriter(fileURL: url, sampleRate: Int(sampleRate), channelCount: 1)
        if onSegment != nil {
            segmentWriter = try WaveWriter(
                fileURL: SegmentNamer.segmentURL(for: url, index: 0),
                sampleRate: Int(sampleRate),
                channelCount: 1
            )
        }

        input.installTap(onBus: 0, bufferSize: 2048, format: recordFormat) { [weak self] buffer, _ in
            guard let self, let channelData = buffer.floatChannelData else { return }
            let samples = WaveWriter.convertToInt16(channelData[0], frameCount: Int(buffer.frameLength))
            self.sampleQueue.async { [weak self] in
                self?.ingest(samples: samples)
            }
        }
        try engine.start()
        isCapturing = true
    }

    /// Roda na fila serial — única consumidora dos writers.
    private func ingest(samples: [Int16]) {
        try? fullWriter?.append(samples: samples)
        guard segmentWriter != nil else { return }
        try? segmentWriter?.append(samples: samples)
        framesInSegment += samples.count
        guard framesInSegment >= framesPerSegment, let full = fullURL else { return }

        try? segmentWriter?.finalize()
        segmentWriter = nil
        let closedURL = SegmentNamer.segmentURL(for: full, index: segmentIndex)
        onSegment?(closedURL, segmentIndex)
        segmentIndex += 1
        framesInSegment = 0
        segmentWriter = try? WaveWriter(
            fileURL: SegmentNamer.segmentURL(for: full, index: segmentIndex),
            sampleRate: Int(segmentSampleRate),
            channelCount: 1
        )
    }

    func stop() throws {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        try sampleQueue.sync {
            try fullWriter?.finalize()
            fullWriter = nil
            if let segment = segmentWriter, let full = fullURL {
                if framesInSegment > 0 {
                    try segment.finalize()
                    onSegment?(SegmentNamer.segmentURL(for: full, index: segmentIndex), segmentIndex)
                } else {
                    // Segmento vazio: descarta.
                    try? segment.finalize()
                    try? FileManager.default.removeItem(at: SegmentNamer.segmentURL(for: full, index: segmentIndex))
                }
                segmentWriter = nil
            }
        }
        onSegment = nil
        fullURL = nil
        isCapturing = false
    }
}

