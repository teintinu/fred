import Foundation

/// Plano de notificação — puro e testável.
struct NotificationPlan: Equatable {
    var identifier: String
    var title: String
    var body: String
    var fireDate: Date
}

/// Lógica pura de planejamento de notificações.
enum NotificationPlanner {
    /// Lembrete de evento: dispara `leadMinutes` antes do início.
    static func planEventReminder(draft: EventDraft, leadMinutes: Int = 10) -> NotificationPlan? {
        guard draft.status == .created else { return nil }
        let fireDate = draft.startDate.addingTimeInterval(-TimeInterval(leadMinutes * 60))
        guard fireDate > Date() else { return nil }
        return NotificationPlan(
            identifier: "fred.event.\(draft.id.uuidString)",
            title: "Compromisso: \(draft.title)",
            body: draft.notes ?? draft.title,
            fireDate: fireDate
        )
    }

    static func planFollowUp(_ followUp: ProposedFollowUp) -> NotificationPlan? {
        guard let dueISO = followUp.dueISO,
              let due = FredISO8601.date(from: dueISO),
              due > Date() else { return nil }
        return NotificationPlan(
            identifier: "fred.followup.\(followUp.id.uuidString)",
            title: "Follow-up",
            body: followUp.text,
            fireDate: due
        )
    }

    /// Remove planos já agendados (deduplicação por identificador).
    static func dedupe(_ plans: [NotificationPlan], existingIdentifiers: Set<String>) -> [NotificationPlan] {
        plans.filter { !existingIdentifiers.contains($0.identifier) }
    }
}
