import XCTest
@testable import Fred

final class NotificationPlannerTests: XCTestCase {
    private func makeDraft(status: EventDraftStatus, startDate: Date) -> EventDraft {
        EventDraft(
            id: UUID(),
            recordingID: UUID(),
            title: "Reunião",
            startDate: startDate,
            endDate: startDate.addingTimeInterval(1800),
            timeZone: "America/Sao_Paulo",
            notes: "sala 3",
            googleEventID: status == .created ? "g1" : nil,
            status: status
        )
    }

    func testEventReminderFiresAtLeadTime() throws {
        let start = Date().addingTimeInterval(3600)
        let draft = makeDraft(status: .created, startDate: start)
        let plan = try XCTUnwrap(NotificationPlanner.planEventReminder(draft: draft, leadMinutes: 10))
        XCTAssertEqual(plan.fireDate.timeIntervalSince(start), -600, accuracy: 1)
        XCTAssertEqual(plan.identifier, "fred.event.\(draft.id.uuidString)")
        XCTAssertEqual(plan.title, "Compromisso: Reunião")
        XCTAssertEqual(plan.body, "sala 3")
    }

    func testReminderOnlyForCreatedDrafts() {
        let start = Date().addingTimeInterval(3600)
        XCTAssertNil(NotificationPlanner.planEventReminder(draft: makeDraft(status: .proposed, startDate: start)))
        XCTAssertNil(NotificationPlanner.planEventReminder(draft: makeDraft(status: .confirmed, startDate: start)))
        XCTAssertNil(NotificationPlanner.planEventReminder(draft: makeDraft(status: .rejected, startDate: start)))
    }

    func testReminderInPastIsNil() {
        let past = Date().addingTimeInterval(-3600)
        XCTAssertNil(NotificationPlanner.planEventReminder(draft: makeDraft(status: .created, startDate: past)))
    }

    func testFollowUpPlanUsesDueDate() throws {
        let due = Date().addingTimeInterval(7200)
        let followUp = ProposedFollowUp(text: "ligar para cliente", dueISO: FredISO8601.string(from: due))
        let plan = try XCTUnwrap(NotificationPlanner.planFollowUp(followUp))
        XCTAssertEqual(plan.fireDate.timeIntervalSince(due), 0, accuracy: 1)
        XCTAssertEqual(plan.body, "ligar para cliente")
    }

    func testFollowUpWithoutDueDateIsNil() {
        XCTAssertNil(NotificationPlanner.planFollowUp(ProposedFollowUp(text: "sem data", dueISO: nil)))
    }

    func testDedupeRemovesAlreadyScheduled() {
        let plans = [
            NotificationPlan(identifier: "a", title: "", body: "", fireDate: Date()),
            NotificationPlan(identifier: "b", title: "", body: "", fireDate: Date()),
        ]
        let result = NotificationPlanner.dedupe(plans, existingIdentifiers: ["a"])
        XCTAssertEqual(result.map(\.identifier), ["b"])
    }
}
