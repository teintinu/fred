import Foundation

/// Resumo estruturado gerado pela LLM (sempre em PT-BR).
struct SummaryResult: Codable, Equatable {
    var summary: String
    var keyPoints: [String]
    var decisions: [String]
    var nextSteps: [String]
    var proposedEvents: [ProposedEvent]
    var followUps: [ProposedFollowUp]
}

/// Evento proposto pela LLM. Nunca é criado no calendário sem confirmação manual.
struct ProposedEvent: Codable, Equatable, Identifiable {
    var id: UUID = UUID()
    var title: String
    var startISO: String
    var endISO: String
    var timeZone: String
    var participants: [String]?
    var notes: String?
}

/// Follow-up proposto pela LLM.
struct ProposedFollowUp: Codable, Equatable, Identifiable {
    var id: UUID = UUID()
    var text: String
    var dueISO: String?
}
