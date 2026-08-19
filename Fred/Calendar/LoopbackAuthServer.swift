import Foundation
import Network

enum LoopbackAuthError: Error, Equatable {
    case noAvailablePort
    case timedOut
    case invalidRequest
}

/// Servidor HTTP mínimo em 127.0.0.1 para receber o callback do OAuth do Google.
/// Fluxo oficial de "desktop app": sem scheme custom, sem domínio — o navegador
/// redireciona para http://127.0.0.1:<porta> e este servidor captura o código.
final class LoopbackAuthServer {
    private let port: UInt16
    private var listener: NWListener?
    private let queue = DispatchQueue(label: "com.fred.loopback")

    init(port: UInt16) {
        self.port = port
    }

    /// Abre o navegador (via `openBrowser`) e aguarda o GET com `code` e `state`.
    func awaitCode(
        timeout: TimeInterval = 300,
        openBrowser: @escaping () -> Void
    ) async throws -> (code: String, state: String) {
        try await withCheckedThrowingContinuation { continuation in
            let lock = NSLock()
            var resumed = false
            let resume: (Result<(String, String), Error>) -> Void = { result in
                lock.lock()
                guard !resumed else {
                    lock.unlock()
                    return
                }
                resumed = true
                lock.unlock()

                FredLogger.log("loopback: resultado=\(result)")
                self.listener?.cancel()
                self.queue.async {
                    self.listener = nil
                }
                switch result {
                case .success(let pair):
                    continuation.resume(returning: pair)
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }

            guard let nwPort = NWEndpoint.Port(rawValue: port) else {
                resume(.failure(LoopbackAuthError.noAvailablePort))
                return
            }
            let listener: NWListener
            do {
                listener = try NWListener(using: .tcp, on: nwPort)
            } catch {
                resume(.failure(LoopbackAuthError.noAvailablePort))
                return
            }
            self.listener = listener

            listener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    FredLogger.log("loopback: porta \(self.port) pronta — abrindo navegador")
                    openBrowser()
                case .failed:
                    FredLogger.log("loopback: falha ao escutar na porta \(self.port)")
                    resume(.failure(LoopbackAuthError.noAvailablePort))
                default:
                    break
                }
            }
            listener.newConnectionHandler = { [weak self] connection in
                guard let self else { return }
                connection.start(queue: self.queue)
                self.receive(on: connection, resume: resume)
            }
            listener.start(queue: queue)

            queue.asyncAfter(deadline: .now() + timeout) {
                resume(.failure(LoopbackAuthError.timedOut))
            }
        }
    }

    private func receive(
        on connection: NWConnection,
        resume: @escaping (Result<(String, String), Error>) -> Void,
        accumulated: Data = Data()
    ) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            var buffer = accumulated
            if let data { buffer.append(data) }

            let requestText = String(data: buffer, encoding: .utf8) ?? ""
            if let pair = Self.parseCode(from: requestText) {
                self.respond(to: connection, success: true) {
                    resume(.success(pair))
                }
            } else if buffer.count > 64 * 1024 || error != nil || isComplete {
                // Sem código na requisição (ou grande demais) — desiste.
                self.respond(to: connection, success: false) {
                    resume(.failure(LoopbackAuthError.invalidRequest))
                }
            } else {
                // A linha de requisição pode chegar dividida em vários chunks — aguarda mais dados.
                self.receive(on: connection, resume: resume, accumulated: buffer)
            }
        }
    }

    private func respond(to connection: NWConnection, success: Bool, completion: @escaping () -> Void) {
        let html = success ? """
        <html><head><meta charset="utf-8"><title>Fred</title></head>
        <body style="font-family:-apple-system;text-align:center;padding-top:80px">
        <h2>✅ Autorização concluída!</h2>
        <p>Pode fechar esta aba e voltar para o Fred.</p>
        </body></html>
        """ : """
        <html><head><meta charset="utf-8"><title>Fred</title></head>
        <body style="font-family:-apple-system;text-align:center;padding-top:80px">
        <h2>❌ Falha na autorização</h2>
        <p>O código de autorização não foi recebido. Volte ao Fred e tente novamente.</p>
        </body></html>
        """
        let body = Data(html.utf8)
        let header = "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n"
        var payload = Data(header.utf8)
        payload.append(body)
        connection.send(content: payload, completion: .contentProcessed { _ in
            connection.cancel()
            completion()
        })
    }

    /// Parser puro: extrai `code` e `state` da requisição HTTP.
    static func parseCode(from rawRequest: String) -> (code: String, state: String)? {
        guard let firstLine = rawRequest.components(separatedBy: "\r\n").first,
              firstLine.hasPrefix("GET "),
              let firstSpace = firstLine.firstIndex(of: " ") else { return nil }
        var pathStart = firstLine.index(after: firstSpace)
        while pathStart < firstLine.endIndex, firstLine[pathStart] == " " {
            pathStart = firstLine.index(after: pathStart)
        }
        guard let pathEnd = firstLine[pathStart...].firstIndex(of: " ") else { return nil }
        let path = String(firstLine[pathStart..<pathEnd])
        guard let components = URLComponents(string: path),
              let items = components.queryItems else { return nil }
        guard let code = items.first(where: { $0.name == "code" })?.value,
              let state = items.first(where: { $0.name == "state" })?.value,
              !code.isEmpty, !state.isEmpty else { return nil }
        return (code, state)
    }

    static func randomPort() -> UInt16 {
        UInt16.random(in: 49_152...60_000)
    }
}
