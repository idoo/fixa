import Foundation
import FixaKit
import Observation
import UIKit

enum Route: Hashable {
    case report
    case review
    case receipt
    case history
    case historyDetail(UUID)
    case about
}

@Observable
@MainActor
final class AppModel {
    let spec: AdapterSpec?
    let options: LaunchOptions
    let history: HistoryStore
    let submission = SubmissionService()

    var path: [Route] = []
    var draft: ReportDraft
    /// Originals picked or taken; `draft.photoJPEG` is their collage.
    private(set) var photos: [UIImage] = []
    var isLocationPickerPresented = false
    /// Set once the user has tried to continue; inline issues show from then on.
    var showIssues = false
    private(set) var sent: SentReport?

    static let maxPhotos = 3
    private static let adapterID = "se.varmdo.ksb"
    private static let contactKey = "fixa.contact"

    init(options: LaunchOptions = .current) {
        self.options = options
        let bundled = AdapterCatalog.bundled()
        spec = bundled.first { $0.id == Self.adapterID } ?? bundled.first
        history = HistoryStore(inMemory: options.demo)
        draft = ReportDraft(adapterID: spec?.id ?? Self.adapterID)
        draft.contact = Self.loadContact()
        if options.demo {
            seedDemo()
        } else if options.liveTest {
            seedLiveTest()
        }
        if let screen = options.screen {
            open(screen)
        }
    }

    // MARK: Flow

    func startReport(tile: AdapterSpec.Tile) {
        if draft.tileID != tile.id {
            draft.tileID = tile.id
            draft.categoryID = tile.categoryID
        }
        submission.reset()
        path = [.report]
    }

    func select(tile: AdapterSpec.Tile) {
        draft.tileID = tile.id
        draft.categoryID = tile.categoryID
    }

    var issues: [ValidationIssue] {
        guard let spec else { return [] }
        return ReportValidator.validate(draft, spec: spec)
    }

    func issue(for field: ValidationIssue.Field) -> ValidationIssue? {
        guard showIssues else { return nil }
        return issues.first { $0.field == field }
    }

    /// Validates and moves to Review; returns false when something needs fixing.
    @discardableResult
    func goToReview() -> Bool {
        showIssues = true
        guard issues.isEmpty else { return false }
        saveContact()
        submission.reset()
        path.append(.review)
        return true
    }

    func send() async {
        guard let spec else { return }
        let dryRun = options.dryRun
        guard let result = await submission.submit(draft, spec: spec, dryRun: dryRun, recordResponses: options.liveTest) else { return }
        sent = result
        if !result.isDryRun {
            history.add(historyItem(for: result))
        }
        path.append(.receipt)
    }

    /// Back to Home with a fresh draft; keeps the remembered contact.
    func finish() {
        let contact = draft.contact
        draft = ReportDraft(adapterID: spec?.id ?? Self.adapterID)
        draft.contact = contact
        photos = []
        showIssues = false
        sent = nil
        submission.reset()
        path = []
    }

    // MARK: Photos

    func addPhotos(_ images: [UIImage]) {
        let room = Self.maxPhotos - photos.count
        guard room > 0 else { return }
        photos.append(contentsOf: images.prefix(room))
        recomposePhoto()
    }

    func removePhoto(at index: Int) {
        guard photos.indices.contains(index) else { return }
        photos.remove(at: index)
        recomposePhoto()
    }

    private func recomposePhoto() {
        draft.photoJPEG = PhotoCollage.combine(photos)
    }

    // MARK: Contact

    func saveContact() {
        guard !options.demo, draft.wantsFeedback, let data = try? JSONEncoder().encode(draft.contact) else { return }
        UserDefaults.standard.set(data, forKey: Self.contactKey)
    }

    private static func loadContact() -> Contact {
        guard let data = UserDefaults.standard.data(forKey: contactKey),
              let contact = try? JSONDecoder().decode(Contact.self, from: data) else { return Contact() }
        return contact
    }

    // MARK: History

    private func historyItem(for result: SentReport) -> HistoryItem {
        HistoryItem(
            id: UUID(),
            date: result.date,
            tileID: draft.tileID,
            description: draft.description,
            locationText: draft.locationText,
            latitude: draft.coordinate?.latitude,
            longitude: draft.coordinate?.longitude,
            caseNumber: result.caseNumber,
            thumbnail: draft.photoJPEG.flatMap { PhotoCollage.thumbnail(from: $0) }
        )
    }

    // MARK: Launch hooks

    private func seedDemo() {
        var demo = DemoData.draft(adapterID: spec?.id ?? Self.adapterID)
        demo.categoryID = spec?.tile(id: demo.tileID)?.categoryID
        draft = demo
        if let image = DemoData.photo {
            photos = [image]
        }
        recomposePhoto()
        history.replaceAll(DemoData.historyItems())
        sent = DemoData.receipt
    }

    /// A clearly marked TEST report with no personal data, for the single real end-to-end check.
    private func seedLiveTest() {
        var test = ReportDraft(adapterID: spec?.id ?? Self.adapterID)
        test.categoryID = "lighting"
        test.description = "TEST — ignorera, testinlämning från app-utveckling. Detta är inget riktigt fel; appen Fixa (öppen källkod) testar att e-tjänsten tar emot anmälningar."
        test.coordinate = Coordinate(latitude: 59.3262, longitude: 18.3856)
        test.locationText = "TEST, Gustavsbergs centrum"
        test.wantsFeedback = true
        test.contact = Contact(firstName: "", lastName: "", phone: "", email: "test@test.se")
        draft = test
        if let image = DemoData.photo {
            photos = [image]
        }
        recomposePhoto()
    }

    private func open(_ screen: LaunchOptions.Screen) {
        switch screen {
        case .home:
            path = []
        case .report:
            path = [.report]
        case .location:
            path = [.report]
            isLocationPickerPresented = true
        case .review:
            path = [.report, .review]
        case .receipt:
            if sent == nil {
                sent = SentReport(caseNumber: nil, date: .now, isDryRun: false)
            }
            path = [.receipt]
        case .history:
            path = [.history]
        case .about:
            path = [.about]
        }
    }
}
