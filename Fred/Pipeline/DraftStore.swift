import Foundation

/// Store de rascunhos de eventos (persistido em JSON). @MainActor para uso direto na UI.
@MainActor
final class DraftStore: ObservableObject {
    @Published private(set) var drafts: [EventDraft] = []
    private let url: URL

    init(url: URL) {
        self.url = url
        load()
    }

    private func load() {
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder.fred.decode([EventDraft].self, from: data) else {
            drafts = []
            return
        }
        drafts = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder.fred.encode(drafts) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }

    func draft(id: UUID) -> EventDraft? {
        drafts.first { $0.id == id }
    }

    /// Adiciona um rascunho SEMPRE no estado `.proposed` — nunca auto-confirmado.
    func add(_ draft: EventDraft) {
        var safeDraft = draft
        safeDraft.status = .proposed
        safeDraft.googleEventID = nil
        drafts.append(safeDraft)
        save()
    }

    func update(_ draft: EventDraft) {
        guard let index = drafts.firstIndex(where: { $0.id == draft.id }) else { return }
        drafts[index] = draft
        save()
    }

    /// Confirmação MANUAL do usuário — único caminho para `.confirmed`.
    func confirm(_ id: UUID) {
        guard let index = drafts.firstIndex(where: { $0.id == id }) else { return }
        drafts[index].status = .confirmed
        save()
    }

    func reject(_ id: UUID) {
        guard let index = drafts.firstIndex(where: { $0.id == id }) else { return }
        drafts[index].status = .rejected
        save()
    }

    func markCreated(id: UUID, googleEventID: String) {
        guard let index = drafts.firstIndex(where: { $0.id == id }) else { return }
        drafts[index].googleEventID = googleEventID
        drafts[index].status = .created
        save()
    }
}
