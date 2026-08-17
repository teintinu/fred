import XCTest
@testable import Fred

final class EventDraftTests: XCTestCase {
    func testValidProposalBecomesProposedDraft() {
        let proposed = ProposedEvent.fixture()
        let draft = EventDraft.from(proposed: proposed, recordingID: UUID())
        XCTAssertNotNil(draft)
        XCTAssertEqual(draft?.status, .proposed)
        XCTAssertEqual(draft?.title, "Reunião de teste")
        XCTAssertEqual(draft?.timeZone, "America/Sao_Paulo")
        XCTAssertNil(draft?.googleEventID)
    }

    func testInvertedDatesAreRejected() {
        let proposed = ProposedEvent(
            title: "X",
            startISO: "2026-08-18T15:00:00-03:00",
            endISO: "2026-08-18T14:00:00-03:00",
            timeZone: "America/Sao_Paulo",
            participants: nil,
            notes: nil
        )
        XCTAssertNil(EventDraft.from(proposed: proposed, recordingID: UUID()))
    }

    func testInvalidISOStringsAreRejected() {
        let proposed = ProposedEvent(
            title: "X",
            startISO: "abc",
            endISO: "def",
            timeZone: "America/Sao_Paulo",
            participants: nil,
            notes: nil
        )
        XCTAssertNil(EventDraft.from(proposed: proposed, recordingID: UUID()))
    }

    func testEmptyTitleIsRejected() {
        let proposed = ProposedEvent(
            title: "   ",
            startISO: "2026-08-18T14:00:00-03:00",
            endISO: "2026-08-18T15:00:00-03:00",
            timeZone: "America/Sao_Paulo",
            participants: nil,
            notes: nil
        )
        XCTAssertNil(EventDraft.from(proposed: proposed, recordingID: UUID()))
    }

    func testEmptyTimezoneFallsBackToSaoPaulo() {
        let proposed = ProposedEvent(
            title: "T",
            startISO: "2026-08-18T14:00:00-03:00",
            endISO: "2026-08-18T15:00:00-03:00",
            timeZone: "",
            participants: nil,
            notes: nil
        )
        XCTAssertEqual(EventDraft.from(proposed: proposed, recordingID: UUID())?.timeZone, "America/Sao_Paulo")
    }

    func testTitleIsTrimmed() {
        let proposed = ProposedEvent(
            title: "  Reunião  ",
            startISO: "2026-08-18T14:00:00-03:00",
            endISO: "2026-08-18T15:00:00-03:00",
            timeZone: "America/Sao_Paulo",
            participants: nil,
            notes: nil
        )
        XCTAssertEqual(EventDraft.from(proposed: proposed, recordingID: UUID())?.title, "Reunião")
    }
}
