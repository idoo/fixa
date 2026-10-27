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
    }

    private static let key = "fixa.draft"

    private static var folder: URL {
        URL.cachesDirectory.appending(path: "fixa-draft", directoryHint: .isDirectory)
    }

    static func save(_ draft: ReportDraft, photoFiles: [String]) {
        var stored = draft
        stored.photoJPEG = nil
        stored.contact = Contact()
        guard let data = try? JSONEncoder().encode(Saved(draft: stored, photoFiles: photoFiles)) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    /// The saved draft with the photos that are still on disk, in their original order.
    static func load() -> (draft: ReportDraft, photos: [UIImage], photoFiles: [String])? {
        guard let data = UserDefaults.standard.data(forKey: key),
              let saved = try? JSONDecoder().decode(Saved.self, from: data) else { return nil }
        var photos: [UIImage] = []
        var files: [String] = []
        for name in saved.photoFiles {
            guard let image = UIImage(contentsOfFile: folder.appending(path: name).path(percentEncoded: false)) else { continue }
            photos.append(image)
            files.append(name)
        }
        return (saved.draft, photos, files)
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
