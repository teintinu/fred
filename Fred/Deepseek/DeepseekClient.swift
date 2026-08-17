import Foundation

enum DeepseekError: Error, Equatable {
    case missingAPIKey
    case invalidResponse
    case apiError(String)
    case emptyContent
}

protocol DeepseekProviding {
    func summarize(transcript: String) async throws -> SummaryResult
    func extractActions(transcript: String) async throws -> (events: [ProposedEvent], followUps: [ProposedFollowUp])
}

/// Cliente da API do Deepseek (compatível com OpenAI).
/// Sessão URLSession injetável para testes (URLProtocol).
final class DeepseekClient: DeepseekProviding {
    private let baseURL = URL(string: "https://api.deepseek.com/chat/completions")!
    private let session: URLSession
    private let apiKeyProvider: () throws -> String

    init(session: URLSession = .shared, apiKeyProvider: @escaping () throws -> String) {
        self.session = session
        self.apiKeyProvider = apiKeyProvider
    }

    func summarize(transcript: String) async throws -> SummaryResult {
        let content = try await request(
            model: .chat,
            system: FredPrompts.summarizeSystem(),
            user: FredPrompts.summarizeUser(transcript),
            json: true
        )
        return try SummaryParser.parse(content)
    }

    func extractActions(transcript: String) async throws -> (events: [ProposedEvent], followUps: [ProposedFollowUp]) {
        let content = try await request(
            model: .reasoner,
            system: FredPrompts.extractSystem(),
            user: FredPrompts.extractUser(transcript),
            json: true
        )
        return try SummaryParser.parseActions(content)
    }

    private func request(model: DeepseekModel, system: String, user: String, json: Bool) async throws -> String {
        let key = try apiKeyProvider()
        guard !key.isEmpty else { throw DeepseekError.missingAPIKey }

        var request = URLRequest(url: baseURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")

        let body = DeepseekRequest(
            model: model.rawValue,
            messages: [
                DeepseekMessage(role: "system", content: system),
                DeepseekMessage(role: "user", content: user),
            ],
            temperature: model == .chat ? 0.3 : 0.0,
            response_format: json ? .init(type: "json_object") : nil
        )
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw DeepseekError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let decoded = try? JSONDecoder().decode(DeepseekResponse.self, from: data)
            throw DeepseekError.apiError(decoded?.error?.message ?? "HTTP \(http.statusCode)")
        }
        guard let dto = try? JSONDecoder().decode(DeepseekResponse.self, from: data) else {
            throw DeepseekError.invalidResponse
        }
        guard let content = dto.choices.first?.message.content, !content.isEmpty else {
            throw DeepseekError.emptyContent
        }
        return content
    }
}
