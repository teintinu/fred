import XCTest
@testable import Fred

@MainActor
final class DraftStoreTests: XCTestCase {
    func testAddAlwaysSetsProposedStatus() throws {
        let root = try makeTempDir()
        defer { removeTempDir(root) }
        let store = DraftStore(url: root.appendingPathComponent("drafts.json"))

        let draft = EventDraft(
            id: UUID(),
            recordingID: UUID(),
            title: "Reunião",
            startDate: Date(),
            endDate: Date().addingTimeInterval(3600),
            timeZone: "America/Sao_Paulo",
            notes: nil,
            googleEventID: "hackeado",
            status: .created // tentativa de pular a confirmação
        )
        store.add(draft)

        XCTAssertEqual(store.drafts.count, 1)
        XCTAssertEqual(store.drafts.first?.status, .proposed, "add() nunca deve preservar status confirmado")
        XCTAssertNil(store.drafts.first?.googleEventID)
    }

    func testConfirmRejectAndMarkCreated() throws {
        let root = try makeTempDir()
        defer { removeTempDir(root) }
        let store = DraftStore(url: root.appendingPathComponent("drafts.json"))

        let proposed = EventDraft.from(proposed: ProposedEvent.fixture(), recordingID: UUID())!
        store.add(proposed)
        XCTAssertEqual(store.drafts.first?.status, .proposed)

        store.confirm(proposed.id)
        XCTAssertEqual(store.drafts.first?.status, .confirmed)

        store.markCreated(id: proposed.id, googleEventID: "evt-1")
        XCTAssertEqual(store.drafts.first?.status, .created)
        XCTAssertEqual(store.drafts.first?.googleEventID, "evt-1")

        store.reject(proposed.id)
        XCTAssertEqual(store.drafts.first?.status, .rejected)
    }

    func testPersistenceAcrossInstances() throws {
        let root = try makeTempDir()
        defer { removeTempDir(root) }
        let url = root.appendingPathComponent("drafts.json")

        let store1 = DraftStore(url: url)
        let draft = EventDraft.from(proposed: ProposedEvent.fixture(), recordingID: UUID())!
        store1.add(draft)
        store1.confirm(draft.id)

        let store2 = DraftStore(url: url)
        XCTAssertEqual(store2.drafts.count, 1)
        XCTAssertEqual(store2.drafts.first?.status, .confirmed)
    }
}
