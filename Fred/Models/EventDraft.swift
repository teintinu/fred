import Foundation

/// Estado de um rascunho de evento.
enum EventDraftStatus: String, Codable, Equatable {
    case proposed      // sugerido pela LLM — ainda NÃO confirmado
    case confirmed     // usuário confirmou manualmente
    case created       // criado no Google Calendar
    case rejected      // usuário descartou
}

/// Rascunho de evento para o Google Calendar.
/// Regra de segurança: só vai para a API no estado `.confirmed`.
struct EventDraft: Identifiable, Codable, Equatable {
    var id: UUID
    var recordingID: UUID
    var title: String
    var startDate: Date
    var endDate: Date
    var timeZone: String
    var notes: String?
    var googleEventID: String?
    var status: EventDraftStatus

    /// Converte uma proposta da LLM em rascunho, validando datas.
    /// Retorna nil se as datas forem inválidas ou invertidas.
    static func from(proposed: ProposedEvent, recordingID: UUID) -> EventDraft? {
        guard let start = FredISO8601.date(from: proposed.startISO),
              let end = FredISO8601.date(from: proposed.endISO),
              end > start else { return nil }
        let title = proposed.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return nil }
        return EventDraft(
            id: UUID(),
            recordingID: recordingID,
            title: title,
            startDate: start,
            endDate: end,
            timeZone: proposed.timeZone.isEmpty ? "America/Sao_Paulo" : proposed.timeZone,
            notes: proposed.notes,
            googleEventID: nil,
            status: .proposed
        )
    }
}
