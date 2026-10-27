import FixaKit
import Foundation
import Observation

/// One report the user pressed Send on, kept on this device only.
struct HistoryItem: Codable, Identifiable, Hashable, Sendable {
    enum Status: String, Codable, Sendable {
        /// Confirmed by the e-service.
        case sent
        /// Saved on this phone; Fixa sends it on its own when the e-service can be reached.
        case waiting
        /// The final step went out but no confirmation came back. Never sent again on its own.
        case maybeSent
        /// Fixa stopped trying on its own; the user decides.
        case notSent
    }

    var id: UUID
    var date: Date
    var tileID: String?
    var description: String
    var locationText: String
    var latitude: Double?
    var longitude: Double?
    var caseNumber: String?
    var thumbnail: Data?
    /// Absent in lists written before 1.1: those were all sent.
    var status: Status = .sent

    private enum CodingKeys: String, CodingKey {
        case id, date, tileID, description, locationText, latitude, longitude, caseNumber, thumbnail, status
    }

    init(
        id: UUID,
        date: Date,
        tileID: String?,
        description: String,
        locationText: String,
        latitude: Double?,
        longitude: Double?,
        caseNumber: String?,
        thumbnail: Data?,
        status: Status = .sent
    ) {
        self.id = id
        self.date = date
        self.tileID = tileID
        self.description = description
        self.locationText = locationText
        self.latitude = latitude
        self.longitude = longitude
        self.caseNumber = caseNumber
        self.thumbnail = thumbnail
        self.status = status
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        date = try c.decode(Date.self, forKey: .date)
        tileID = try c.decodeIfPresent(String.self, forKey: .tileID)
        description = try c.decode(String.self, forKey: .description)
        locationText = try c.decode(String.self, forKey: .locationText)
        latitude = try c.decodeIfPresent(Double.self, forKey: .latitude)
        longitude = try c.decodeIfPresent(Double.self, forKey: .longitude)
        caseNumber = try c.decodeIfPresent(String.self, forKey: .caseNumber)
        thumbnail = try c.decodeIfPresent(Data.self, forKey: .thumbnail)
        status = try c.decodeIfPresent(Status.self, forKey: .status) ?? .sent
    }
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

    /// Changes one entry in place (status, case number); no-op when it was removed meanwhile.
    func update(id: UUID, _ change: (inout HistoryItem) -> Void) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        change(&items[index])
        save()
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

/// A report the user pressed Send on that the e-service has not confirmed yet: the exact draft
/// (text, place, combined photo, contact) so it can be sent later without the user's help.
struct PendingReport: Codable, Identifiable, Sendable {
    /// Same id as its `HistoryItem`.
    var id: UUID
    var draft: ReportDraft
    var createdAt: Date
    /// Sends tried so far, the user's own first Send included.
    var attempts: Int
    /// Earliest time for the next automatic try, back-off and jitter included.
    var nextAttemptAt: Date
    /// No automatic sending: the final step may have gone through (`.uncertain`), the error won't
    /// pass by retrying, or the tries ran out. Only an explicit tap sends it again.
    var held: Bool
    /// Set on disk right before the final step goes out, cleared once its outcome is recorded.
    /// Still set at launch: the app died mid-send, so the report may have been sent.
    var finalSendAt: Date? = nil
    /// The e-service's own `Retry-After`: not even a manual "Try again" goes before it.
    var serverRetryAfter: Date? = nil
}

/// One JSON file per pending report in Application Support/Fixa/Outbox, so reports survive the
/// app being closed. Readable after the first unlock, so a send can finish in the background.
/// The folder and every file are excluded from iCloud/computer backups: they hold the photo and
/// the reply details. Demo mode keeps everything in memory.
@Observable
@MainActor
final class OutboxStore {
    private(set) var items: [PendingReport] = []
    private let directory: URL?

    init(inMemory: Bool = false) {
        directory = inMemory
            ? nil
            : URL.applicationSupportDirectory.appending(path: "Fixa/Outbox", directoryHint: .isDirectory)
        load()
    }

    func item(id: UUID) -> PendingReport? {
        items.first { $0.id == id }
    }

    /// Adds or replaces by id. Returns false when the file could not be written.
    @discardableResult
    func put(_ item: PendingReport) -> Bool {
        if let index = items.firstIndex(where: { $0.id == item.id }) {
            items[index] = item
        } else {
            items.append(item)
        }
        return write(item)
    }

    func remove(_ ids: Set<UUID>) {
        items.removeAll { ids.contains($0.id) }
        guard let directory else { return }
        for id in ids {
            try? FileManager.default.removeItem(at: directory.appending(path: "\(id.uuidString).json"))
        }
    }

    func deleteAll() {
        items = []
        guard let directory else { return }
        try? FileManager.default.removeItem(at: directory)
    }

    private func load() {
        guard let directory,
              let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path(percentEncoded: false)) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        items = names
            .filter { $0.hasSuffix(".json") }
            .compactMap { name in
                guard let data = try? Data(contentsOf: directory.appending(path: name)) else { return nil }
                return try? decoder.decode(PendingReport.self, from: data)
            }
            .sorted { $0.createdAt < $1.createdAt }
    }

    private func write(_ item: PendingReport) -> Bool {
        guard var directory else { return true }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try Self.excludeFromBackup(&directory)
            var file = directory.appending(path: "\(item.id.uuidString).json")
            try encoder.encode(item).write(
                to: file,
                options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
            )
            // An atomic write replaces the file, so the flag is set again on every write.
            try Self.excludeFromBackup(&file)
            return true
        } catch {
            return false
        }
    }

    private static func excludeFromBackup(_ url: inout URL) throws {
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try url.setResourceValues(values)
    }
}
