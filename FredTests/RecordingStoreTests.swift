import XCTest
@testable import Fred

final class RecordingStoreTests: XCTestCase {
    func testAddUpdateListDelete() throws {
        let root = try makeTempDir()
        defer { removeTempDir(root) }
        let store = RecordingStore(root: root)

        let url = store.nextRecordingURL()
        XCTAssertTrue(url.pathExtension == "wav")
        let recording = Recording.fixture(fileName: url.lastPathComponent)
        store.add(recording)
        XCTAssertEqual(store.all().count, 1)

        var updated = recording
        updated.status = .summarized
        store.update(updated)
        XCTAssertEqual(store.recording(withID: recording.id)?.status, .summarized)

        store.delete(id: recording.id)
        XCTAssertTrue(store.all().isEmpty)
    }

    func testPersistenceAcrossInstances() throws {
        let root = try makeTempDir()
        defer { removeTempDir(root) }
        let store1 = RecordingStore(root: root)
        let recording = Recording.fixture(fileName: "rec.wav")
        store1.add(recording)

        let store2 = RecordingStore(root: root)
        XCTAssertEqual(store2.all().count, 1)
        XCTAssertEqual(store2.all().first?.id, recording.id)
        XCTAssertEqual(store2.all().first?.status, .recorded)
    }

    func testRetentionRemovesOldRecordings() throws {
        let root = try makeTempDir()
        defer { removeTempDir(root) }
        let store = RecordingStore(root: root)

        let old = Recording.fixture(
            fileName: "old.wav",
            startDate: Date().addingTimeInterval(-40 * 86_400)
        )
        let recent = Recording.fixture(fileName: "recent.wav", startDate: Date())
        store.add(old)
        store.add(recent)

        let removed = store.enforceRetention(days: 30)
        XCTAssertEqual(removed, 1)
        XCTAssertEqual(store.all().count, 1)
        XCTAssertEqual(store.all().first?.id, recent.id)
    }

    func testCorruptManifestLoadsEmpty() throws {
        let root = try makeTempDir()
        defer { removeTempDir(root) }
        try Data("isto não é json".utf8).write(to: root.appendingPathComponent("recordings.json"))

        let store = RecordingStore(root: root)
        XCTAssertTrue(store.all().isEmpty)
    }
}
