import Foundation

enum CalendarAPIError: Error, Equatable {
    case http(Int)
    case invalidResponse
    /// Regra de segurança violada: tentativa de criar evento sem confirmação manual.
    case eventCreatedWithoutConfirmation
}

/// Evento resumido retornado pela listagem (usado no teste de conexão).
struct CalendarEventSummary: Equatable, Codable {
    var id: String
    var summary: String?
    var start: String?
}

protocol CalendarProviding {
    /// Cria o evento no Google Calendar. Retorna o `googleEventID`.
    /// Lança `eventCreatedWithoutConfirmation` se o draft não estiver `.confirmed`.
    func createEvent(_ draft: EventDraft, calendarID: String) async throws -> String
    /// Lista os próximos eventos (teste de conexão).
    func listUpcomingEvents(calendarID: String, maxResults: Int) async throws -> [CalendarEventSummary]
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

    func listUpcomingEvents(calendarID: String = "primary", maxResults: Int = 10) async throws -> [CalendarEventSummary] {
        let token = try await oauth.accessToken()
        var components = URLComponents(string: "https://www.googleapis.com/calendar/v3/calendars/\(calendarID)/events")!
        components.queryItems = [
            URLQueryItem(name: "timeMin", value: FredISO8601.string(from: Date())),
            URLQueryItem(name: "maxResults", value: String(maxResults)),
            URLQueryItem(name: "singleEvents", value: "true"),
            URLQueryItem(name: "orderBy", value: "startTime"),
        ]
        var request = URLRequest(url: components.url!)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        FredLogger.log("listUpcomingEvents: GET \(components.url?.absoluteString ?? "?")")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw CalendarAPIError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            FredLogger.log("listUpcomingEvents: HTTP \(http.statusCode) body=\(String(data: data, encoding: .utf8)?.prefix(400) ?? "")")
            throw CalendarAPIError.http(http.statusCode)
        }
        FredLogger.log("listUpcomingEvents: HTTP 200, \(data.count) bytes")

        struct DTO: Decodable {
            struct Item: Decodable {
                struct Start: Decodable {
                    var dateTime: String?
                    var date: String?
                }
                var id: String
                var summary: String?
                var start: Start?
            }
            var items: [Item]?
        }
        guard let dto = try? JSONDecoder().decode(DTO.self, from: data) else {
            throw CalendarAPIError.invalidResponse
        }
        return (dto.items ?? []).map {
            CalendarEventSummary(
                id: $0.id,
                summary: $0.summary,
                start: $0.start?.dateTime ?? $0.start?.date
            )
        }
    }
}
