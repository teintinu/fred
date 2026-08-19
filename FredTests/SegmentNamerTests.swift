import XCTest
@testable import Fred

final class SegmentNamerTests: XCTestCase {
    func testSegmentURLNaming() {
        let full = URL(fileURLWithPath: "/tmp/rec-abc.wav")
        XCTAssertEqual(
            SegmentNamer.segmentURL(for: full, index: 0).lastPathComponent,
            "rec-abc.seg-000.wav"
        )
        XCTAssertEqual(
            SegmentNamer.segmentURL(for: full, index: 42).lastPathComponent,
            "rec-abc.seg-042.wav"
        )
        // mesmo diretório do arquivo completo
        XCTAssertEqual(
            SegmentNamer.segmentURL(for: full, index: 1).deletingLastPathComponent().path,
            "/tmp"
        )
    }

    func testFramesConversion() {
        XCTAssertEqual(SegmentNamer.frames(for: 12, sampleRate: 16_000), 192_000)
        XCTAssertEqual(SegmentNamer.frames(for: 0.5, sampleRate: 16_000), 8_000)
        // nunca zero
        XCTAssertEqual(SegmentNamer.frames(for: 0, sampleRate: 16_000), 1)
    }
}
