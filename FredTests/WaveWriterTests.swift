import XCTest
@testable import Fred

final class WaveWriterTests: XCTestCase {
    func testHeaderAndSizesAreCorrect() throws {
        let dir = try makeTempDir()
        defer { removeTempDir(dir) }
        let url = dir.appendingPathComponent("test.wav")

        let writer = try WaveWriter(fileURL: url, sampleRate: 16_000, channelCount: 1)
        let samples = [Int16](repeating: 100, count: 800) // 1600 bytes por bloco
        try writer.append(samples: samples)
        try writer.append(samples: samples) // 3200 bytes no total
        try writer.finalize()

        let data = try Data(contentsOf: url)
        XCTAssertEqual(data.count, 44 + 3200)
        XCTAssertEqual(String(data: data.subdata(in: 0..<4), encoding: .ascii), "RIFF")
        XCTAssertEqual(String(data: data.subdata(in: 8..<12), encoding: .ascii), "WAVE")
        XCTAssertEqual(String(data: data.subdata(in: 36..<40), encoding: .ascii), "data")

        let channels = data.subdata(in: 22..<24).withUnsafeBytes { $0.load(as: UInt16.self) }
        XCTAssertEqual(channels, 1)
        let sampleRate = data.subdata(in: 24..<28).withUnsafeBytes { $0.load(as: UInt32.self) }
        XCTAssertEqual(sampleRate, 16_000)
        let byteRate = data.subdata(in: 28..<32).withUnsafeBytes { $0.load(as: UInt32.self) }
        XCTAssertEqual(byteRate, 32_000)
        let bits = data.subdata(in: 34..<36).withUnsafeBytes { $0.load(as: UInt16.self) }
        XCTAssertEqual(bits, 16)
        let riffSize = data.subdata(in: 4..<8).withUnsafeBytes { $0.load(as: UInt32.self) }
        XCTAssertEqual(riffSize, 36 + 3200)
        let dataSize = data.subdata(in: 40..<44).withUnsafeBytes { $0.load(as: UInt32.self) }
        XCTAssertEqual(dataSize, 3200)
    }

    func testFloatBufferConversionAndClamping() throws {
        let dir = try makeTempDir()
        defer { removeTempDir(dir) }
        let url = dir.appendingPathComponent("test.wav")

        let writer = try WaveWriter(fileURL: url, sampleRate: 8_000, channelCount: 1)
        var floats: [Float] = [0.5, -0.5, 2.0, -2.0]
        try floats.withUnsafeBufferPointer { buffer in
            try writer.append(floatBuffer: buffer.baseAddress!, frameCount: floats.count)
        }
        try writer.finalize()

        let data = try Data(contentsOf: url)
        let samples = data.subdata(in: 44..<52).withUnsafeBytes { Array($0.bindMemory(to: Int16.self)) }
        XCTAssertEqual(samples, [16383, -16383, 32767, -32767])
    }

    func testAppendAfterFinalizeThrows() throws {
        let dir = try makeTempDir()
        defer { removeTempDir(dir) }
        let url = dir.appendingPathComponent("test.wav")

        let writer = try WaveWriter(fileURL: url, sampleRate: 8_000, channelCount: 1)
        try writer.finalize()
        XCTAssertThrowsError(try writer.append(samples: [1, 2, 3])) { error in
            XCTAssertEqual(error as? WaveWriterError, .fileNotOpen)
        }
    }
}
