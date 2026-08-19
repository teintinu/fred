import Foundation
import XCTest
@testable import Fred

// MARK: - Stub de URLProtocol

final class URLProtocolMock: URLProtocol {
    static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    /// Lê o corpo do request. URLSession converte `httpBody` em `httpBodyStream`
    /// ao passar pela URLProtocol — por isso é preciso verificar os dois.
    static func bodyData(of request: URLRequest) -> Data? {
        if let data = request.httpBody { return data }
        guard let stream = request.httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: buffer.count)
            if read <= 0 { break }
            data.append(buffer, count: read)
        }
        return data.isEmpty ? nil : data
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = URLProtocolMock.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

extension URLSession {
    static func mockSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [URLProtocolMock.self]
        return URLSession(configuration: config)
    }
}

// MARK: - Keychain em memória

final class MockKeychain: KeychainStoring {
    var values: [String: String] = [:]

    func set(_ value: String, for key: String) throws { values[key] = value }
    func get(_ key: String) throws -> String? { values[key] }
    func delete(_ key: String) throws { values.removeValue(forKey: key) }
}

// MARK: - Mocks do pipeline

struct MockTranscriber: Transcriber {
    var result: TranscriptionResult
    var error: TranscriptionError?

    func transcribe(fileURL: URL) async throws -> TranscriptionResult {
        if let error { throw error }
        return result
    }
}

final class MockDeepseek: DeepseekProviding {
    var summaryResult: SummaryResult
    var events: [ProposedEvent]
    var followUps: [ProposedFollowUp]
    var error: DeepseekError?
    var liveSummaryResult: String
    var pingResult: String
    private(set) var summarizeCallCount = 0
    private(set) var extractCallCount = 0
    private(set) var liveSummaryCallCount = 0
    private(set) var pingCallCount = 0

    init(
        summaryResult: SummaryResult = .fixture,
        events: [ProposedEvent] = [],
        followUps: [ProposedFollowUp] = [],
        error: DeepseekError? = nil,
        liveSummaryResult: String = "resumo ao vivo",
        pingResult: String = "ok"
    ) {
        self.summaryResult = summaryResult
        self.events = events
        self.followUps = followUps
        self.error = error
        self.liveSummaryResult = liveSummaryResult
        self.pingResult = pingResult
    }

    func summarize(transcript: String) async throws -> SummaryResult {
        summarizeCallCount += 1
        if let error { throw error }
        return summaryResult
    }

    func extractActions(transcript: String) async throws -> (events: [ProposedEvent], followUps: [ProposedFollowUp]) {
        extractCallCount += 1
        if let error { throw error }
        return (events, followUps)
    }

    func liveSummary(transcript: String) async throws -> String {
        liveSummaryCallCount += 1
        if let error { throw error }
        return liveSummaryResult
    }

    func ping() async throws -> String {
        pingCallCount += 1
        if let error { throw error }
        return pingResult
    }
}

// MARK: - Fixtures

extension SummaryResult {
    static var fixture: SummaryResult {
        SummaryResult(
            summary: "Resumo de teste",
            keyPoints: ["Ponto 1"],
            decisions: [],
            nextSteps: [],
            proposedEvents: [],
            followUps: []
        )
    }
}

extension ProposedEvent {
    static func fixture(
        start: String = "2026-08-18T14:00:00-03:00",
        end: String = "2026-08-18T15:00:00-03:00"
    ) -> ProposedEvent {
        ProposedEvent(
            title: "Reunião de teste",
            startISO: start,
            endISO: end,
            timeZone: "America/Sao_Paulo",
            participants: nil,
            notes: nil
        )
    }
}

extension Recording {
    static func fixture(fileName: String, startDate: Date = Date(), status: RecordingStatus = .recorded) -> Recording {
        Recording(
            id: UUID(),
            fileName: fileName,
            source: .microphone,
            appBundleID: nil,
            appName: nil,
            startDate: startDate,
            endDate: nil,
            durationSeconds: nil,
            languageDetected: nil,
            status: status,
            transcript: nil,
            summary: nil,
            errorMessage: nil
        )
    }
}

// MARK: - Utilidades

func makeTempDir() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("fred-tests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

func removeTempDir(_ url: URL) {
    try? FileManager.default.removeItem(at: url)
}
