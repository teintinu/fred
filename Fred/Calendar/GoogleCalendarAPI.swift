import Foundation

enum CalendarAPIError: Error, Equatable {
    case http(Int)
    case invalidResponse
    /// Regra de segurança violada: tentativa de criar evento sem confirmação manual.
    case eventCreatedWithoutConfirmation
}

protocol CalendarProviding {
    /// Cria o evento no Google Calendar. Retorna o `googleEventID`.
    /// Lança `eventCreatedWithoutConfirmation` se o draft não estiver `.confirmed`.
    func createEvent(_ draft: EventDraft, calendarID: String) async throws -> String
}

/// Cliente REST do Google Calendar v3.
final class GoogleCalendarAPI: CalendarProviding {
    struct EventPayload: Codable, Equatable {
        struct DateTime: Codable, Equatable {
            var dateTime: String
            var timeZone: String
        }

        var summary: String
        var description: String?
        var start: DateTime
        var end: DateTime
    }

    private let session: URLSession
    private let oauth: GoogleOAuth

    init(session: URLSession = .shared, oauth: GoogleOAuth) {
        self.session = session
        self.oauth = oauth
    }

    func createEvent(_ draft: EventDraft, calendarID: String = "primary") async throws -> String {
        guard draft.status == .confirmed else {
            throw CalendarAPIError.eventCreatedWithoutConfirmation
        }
        let token = try await oauth.accessToken()
        let url = URL(string: "https://www.googleapis.com/calendar/v3/calendars/\(calendarID)/events")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload = EventPayload(
            summary: draft.title,
            description: draft.notes,
            start: .init(dateTime: FredISO8601.string(from: draft.startDate), timeZone: draft.timeZone),
            end: .init(dateTime: FredISO8601.string(from: draft.endDate), timeZone: draft.timeZone)
        )
        request.httpBody = try JSONEncoder().encode(payload)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw CalendarAPIError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else { throw CalendarAPIError.http(http.statusCode) }
        struct EventDTO: Decodable {
            var id: String
        }
        guard let dto = try? JSONDecoder().decode(EventDTO.self, from: data) else {
            throw CalendarAPIError.invalidResponse
        }
        return dto.id
    }
}
