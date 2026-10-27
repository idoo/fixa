import FixaKit
import Foundation
import UIKit

/// The unsent report, kept across app kills. Text fields go to UserDefaults; each original
/// photo is one JPEG in Caches/fixa-draft (purgeable: if iOS clears it, the text still restores).
/// Photos are re-encoded by `UIImage.jpegData`, which drops EXIF/GPS, and stored with complete file
/// protection in a folder excluded from backup. The contact is never stored here: it lives in the profile.
@MainActor
enum DraftStore {
    private struct Saved: Codable {
        var draft: ReportDraft
        var photoFiles: [String]
        /// Absent in drafts saved before build 9.
        var pinIsAutomatic: Bool?
        var placeTextIsTyped: Bool?
    }

    struct Restored {
        var draft: ReportDraft
        var photos: [UIImage]
        var photoFiles: [String]
        var pinIsAutomatic: Bool
        var placeTextIsTyped: Bool
    }

    private static let key = "fixa.draft"

    private static var folder: URL {
        URL.cachesDirectory.appending(path: "fixa-draft", directoryHint: .isDirectory)
    }

    static func save(_ draft: ReportDraft, photoFiles: [String], pinIsAutomatic: Bool, placeTextIsTyped: Bool) {
        var stored = draft
        stored.photoJPEG = nil
        stored.contact = Contact()
        let saved = Saved(draft: stored, photoFiles: photoFiles, pinIsAutomatic: pinIsAutomatic, placeTextIsTyped: placeTextIsTyped)
        guard let data = try? JSONEncoder().encode(saved) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    /// The saved draft without its photos (cheap; for comparing).
    static func loadDraft() -> ReportDraft? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(Saved.self, from: data).draft
    }

    /// The saved draft with the photos that are still on disk, in their original order.
    static func load() -> Restored? {
        guard let data = UserDefaults.standard.data(forKey: key),
              let saved = try? JSONDecoder().decode(Saved.self, from: data) else { return nil }
        var photos: [UIImage] = []
        var files: [String] = []
        for name in saved.photoFiles {
            guard let image = UIImage(contentsOfFile: folder.appending(path: name).path(percentEncoded: false)) else { continue }
            photos.append(image)
            files.append(name)
        }
        // Before build 9 a restored place text without a pin was taken as typed.
        let typed = saved.placeTextIsTyped
            ?? (saved.draft.coordinate == nil && !saved.draft.locationText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        return Restored(draft: saved.draft, photos: photos, photoFiles: files,
                        pinIsAutomatic: saved.pinIsAutomatic ?? false, placeTextIsTyped: typed)
    }

    /// Writes one original photo; returns its file name, or nil if it could not be stored.
    static func writePhoto(_ image: UIImage) -> String? {
        guard let data = image.jpegData(compressionQuality: 0.85) else { return nil }
        let name = "\(UUID().uuidString).jpg"
        do {
            try prepareFolder()
            try data.write(to: folder.appending(path: name), options: [.atomic, .completeFileProtection])
            return name
        } catch {
            return nil
        }
    }

    private static func prepareFolder() throws {
        var url = folder
        try FileManager.default.createDirectory(
            at: url, withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.complete]
        )
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try url.setResourceValues(values)
    }

    static func deletePhoto(_ name: String) {
        try? FileManager.default.removeItem(at: folder.appending(path: name))
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
        try? FileManager.default.removeItem(at: folder)
    }
}
