import Foundation
import Observation

/// One sent report, kept on this device only.
struct HistoryItem: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    var date: Date
    var tileID: String?
    var description: String
    var locationText: String
    var latitude: Double?
    var longitude: Double?
    var caseNumber: String?
    var thumbnail: Data?
}

/// JSON file in Application Support. Demo mode keeps everything in memory.
@Observable
@MainActor
final class HistoryStore {
    private(set) var items: [HistoryItem] = []
    private let fileURL: URL?

    init(inMemory: Bool = false) {
        if inMemory {
            fileURL = nil
        } else {
            let dir = URL.applicationSupportDirectory.appending(path: "Fixa", directoryHint: .isDirectory)
            fileURL = dir.appending(path: "history.json")
        }
        load()
    }

    func add(_ item: HistoryItem) {
        items.insert(item, at: 0)
        save()
    }

    func delete(_ ids: Set<UUID>) {
        items.removeAll { ids.contains($0.id) }
        save()
    }

    /// Empties the list and removes the file itself rather than writing an empty one.
    func deleteAll() {
        items = []
        guard let fileURL else { return }
        try? FileManager.default.removeItem(at: fileURL)
    }

    func item(id: UUID) -> HistoryItem? {
        items.first { $0.id == id }
    }

    func replaceAll(_ newItems: [HistoryItem]) {
        items = newItems.sorted { $0.date > $1.date }
        save()
    }

    private func load() {
        guard let fileURL, let data = try? Data(contentsOf: fileURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        items = (try? decoder.decode([HistoryItem].self, from: data)) ?? []
    }

    private func save() {
        guard let fileURL else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try encoder.encode(items).write(to: fileURL, options: [.atomic, .completeFileProtection])
        } catch {
            // History is a convenience; a failed write must not block reporting.
        }
    }
}
