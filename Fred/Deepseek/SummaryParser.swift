import Foundation

enum SummaryParserError: Error, Equatable {
    case invalidJSON
    case emptySummary
    case eventInvalidDates(String)
}

/// Parser estrito do JSON da LLM. Valida estrutura e datas.
/// Nunca executa ações — apenas converte dados.
enum SummaryParser {
    private struct RawSummary: Codable {
        struct RawEvent: Codable {
            var title: String?
            var startISO: String?
            var endISO: String?
            var timeZone: String?
            var participants: [String]?
            var notes: String?
        }
        struct RawFollowUp: Codable {
            var text: String?
            var dueISO: String?
        }

        var summary: String?
        var keyPoints: [String]?
        var decisions: [String]?
        var nextSteps: [String]?
        var proposedEvents: [RawEvent]?
        var followUps: [RawFollowUp]?
    }

    private static func cleanedContent(_ content: String) -> String {
        content
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func parse(_ content: String) throws -> SummaryResult {
        let cleaned = cleanedContent(content)
        guard let data = cleaned.data(using: .utf8),
              let raw = try? JSONDecoder().decode(RawSummary.self, from: data) else {
            throw SummaryParserError.invalidJSON
        }
        guard let summary = raw.summary?.trimmingCharacters(in: .whitespacesAndNewlines),
              !summary.isEmpty else {
            throw SummaryParserError.emptySummary
        }

        var events: [ProposedEvent] = []
        for rawEvent in raw.proposedEvents ?? [] {
            guard let title = rawEvent.title?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !title.isEmpty else { continue }
            guard let start = rawEvent.startISO, FredISO8601.date(from: start) != nil else {
                throw SummaryParserError.eventInvalidDates(title)
            }
            guard let end = rawEvent.endISO, FredISO8601.date(from: end) != nil else {
                throw SummaryParserError.eventInvalidDates(title)
            }
            events.append(ProposedEvent(
                title: title,
                startISO: start,
                endISO: end,
                timeZone: rawEvent.timeZone ?? "America/Sao_Paulo",
                participants: rawEvent.participants,
                notes: rawEvent.notes
            ))
        }

        let followUps = (raw.followUps ?? []).compactMap { raw -> ProposedFollowUp? in
            guard let text = raw.text?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !text.isEmpty else { return nil }
            return ProposedFollowUp(text: text, dueISO: raw.dueISO)
        }

        return SummaryResult(
            summary: summary,
            keyPoints: raw.keyPoints ?? [],
            decisions: raw.decisions ?? [],
            nextSteps: raw.nextSteps ?? [],
            proposedEvents: events,
            followUps: followUps
        )
    }

    static func parseActions(_ content: String) throws -> (events: [ProposedEvent], followUps: [ProposedFollowUp]) {
        let result = try parse(content)
        return (result.proposedEvents, result.followUps)
    }
}
