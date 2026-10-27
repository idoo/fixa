import CoreLocation
import FixaKit
import Foundation
import Observation
import UIKit

enum Route: Hashable {
    case report
    case review
    case receipt
    case history
    case historyDetail(UUID)
    case about
    case settings
    case contactDetails
    case language
    case textSize
    case privacy
}

@Observable
@MainActor
final class AppModel {
    /// The municipality adapter: bundled, or a newer accepted copy from GitHub (`AdapterStore`).
    let adapters = AdapterStore(adapterID: AppModel.adapterID)
    var spec: AdapterSpec? { adapters.spec }
    /// What Home shows about the municipality's e-service; `-FixaStatus` forces one for screenshots.
    var adapterStatus: AdapterStatus { options.status ?? adapters.status }
    let options: LaunchOptions
    let history: HistoryStore
    let submission = SubmissionService()

    var path: [Route] = []
    /// What the report sends. `contact` always mirrors the profile while a reply is wanted and is
    /// empty otherwise, so turning the toggle off never sends (or deletes) the saved details.
    var draft: ReportDraft {
        get { draftStorage }
        set {
            var next = newValue
            next.contact = next.wantsFeedback ? profileStorage : Contact()
            draftStorage = next
            scheduleDraftSave()
        }
    }
    private var draftStorage: ReportDraft
    /// Optional reply details, saved on this phone (UserDefaults `fixa.contact`) as they change.
    var profile: Contact {
        get { profileStorage }
        set {
            profileStorage = newValue
            if draftStorage.wantsFeedback {
                draftStorage.contact = newValue
            }
            scheduleProfileSave()
        }
    }
    private var profileStorage: Contact
    /// Originals picked or taken; `draft.photoJPEG` is their collage.
    private(set) var photos: [UIImage] = []
    /// Draft copies of `photos` in Caches, same order; empty when drafts aren't persisted.
    @ObservationIgnored private var photoFiles: [String] = []
    var isLocationPickerPresented = false
    /// True while a new report fills in the current location on its own.
    private(set) var isFindingLocation = false
    /// Set once the user has tried to continue; inline issues show from then on.
    var showIssues = false
    private(set) var sent: SentReport?
    /// Text size, appearance, contrast, bold, motion and vibration (UserDefaults `fixa.display`).
    var display: DisplaySettings {
        didSet {
            guard persists, display != oldValue else { return }
            display.save()
        }
    }
    /// Off: contact details serve only the report being written, are never saved and are
    /// forgotten when it is finished (UserDefaults `fixa.rememberDetails`, default on).
    var rememberDetails: Bool {
        didSet {
            guard rememberDetails != oldValue else { return }
            if persists {
                UserDefaults.standard.set(rememberDetails, forKey: Self.rememberKey)
            }
            saveProfileNow()
        }
    }
    /// The chosen UI language; `nil` is "Same as iPhone" (UserDefaults `fixa.language`).
    /// Slice Language makes the UI follow it.
    var language: AppLanguage? {
        didSet {
            guard persists, language != oldValue else { return }
            if let language {
                UserDefaults.standard.set(language.rawValue, forKey: AppLanguage.storageKey)
            } else {
                UserDefaults.standard.removeObject(forKey: AppLanguage.storageKey)
            }
        }
    }
    /// The language the app shows now.
    var effectiveLanguage: AppLanguage { language ?? .system }
    /// The first-launch disclaimer; shown once (UserDefaults `fixa.onboarded`), again from About.
    var isOnboardingPresented: Bool

    @ObservationIgnored private var profileSaveTask: Task<Void, Never>?
    @ObservationIgnored private var draftSaveTask: Task<Void, Never>?

    static let maxPhotos = 3
    private static let adapterID = "se.varmdo.ksb"
    private static let contactKey = "fixa.contact"
    private static let rememberKey = "fixa.rememberDetails"
    private static let onboardedKey = "fixa.onboarded"

    init(options: LaunchOptions = .current) {
        self.options = options
        history = HistoryStore(inMemory: options.demo)
        profileStorage = Self.loadContact()
        var savedDisplay = DisplaySettings.load()
        if let size = options.textSize {
            savedDisplay.textSize = size
        }
        display = savedDisplay
        rememberDetails = UserDefaults.standard.object(forKey: Self.rememberKey) as? Bool ?? true
        language = UserDefaults.standard.string(forKey: AppLanguage.storageKey).flatMap(AppLanguage.init(rawValue:))
        // Demo, test and screenshot launches skip it unless they ask for `-FixaScreen onboarding`.
        if options.screen == .onboarding {
            isOnboardingPresented = true
        } else if options.demo || options.liveTest || options.screen != nil {
            isOnboardingPresented = false
        } else {
            isOnboardingPresented = !UserDefaults.standard.bool(forKey: Self.onboardedKey)
        }
        draftStorage = ReportDraft(adapterID: adapters.spec?.id ?? Self.adapterID)
        draftStorage = freshDraft()
        if options.demo {
            seedDemo()
        } else if options.liveTest {
            seedLiveTest()
        } else if options.screen == nil {
            restoreDraft()
        }
        if let screen = options.screen {
            open(screen)
        }
    }

    /// Drafts and the profile are written only for real use, never for demo or live-test launches.
    private var persists: Bool { !options.demo && !options.liveTest }

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
        saveProfileNow()
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
            clearSavedDraft()
        }
        path.append(.receipt)
    }

    /// Back to Home with a fresh draft; the profile stays unless "Remember my details" is off.
    func finish() {
        sent = nil
        photos = []
        clearSavedDraft()
        if !rememberDetails {
            profileStorage = Contact()
        }
        draft = freshDraft()
        showIssues = false
        submission.reset()
        path = []
    }

    /// A new report: replies default to on when the profile already has a usable e-mail.
    private func freshDraft() -> ReportDraft {
        var fresh = ReportDraft(adapterID: spec?.id ?? Self.adapterID)
        fresh.wantsFeedback = profileHasEmail
        fresh.contact = fresh.wantsFeedback ? profileStorage : Contact()
        return fresh
    }

    // MARK: Onboarding

    func finishOnboarding() {
        isOnboardingPresented = false
        if persists {
            UserDefaults.standard.set(true, forKey: Self.onboardedKey)
        }
    }

    /// "How Fixa works" in About.
    func showOnboarding() {
        isOnboardingPresented = true
    }

    // MARK: Deleting data

    /// Removes the sent-reports list from this phone (the file itself, not an empty list).
    func clearHistory() {
        history.deleteAll()
    }

    /// Contact details, the unsent report with its photos and the sent-reports list leave this
    /// phone. Language and display settings stay. Not while a report is being sent.
    func deleteAllData() {
        guard !submission.isSending else { return }
        profileSaveTask?.cancel()
        draftSaveTask?.cancel()
        profileStorage = Contact()
        photos = []
        photoFiles = []
        if persists {
            UserDefaults.standard.removeObject(forKey: Self.contactKey)
            DraftStore.clear()
        }
        draftStorage = freshDraft()
        showIssues = false
        history.deleteAll()
        sent = nil
        submission.reset()
    }

    // MARK: Location

    /// On a new report, fills in the current place and address when location is already allowed.
    /// Never asks for permission: that prompt stays on the explicit "Use my location".
    func prefillLocationIfAllowed() async {
        guard persists, let spec, draft.coordinate == nil, !isFindingLocation else { return }
        let status = CLLocationManager().authorizationStatus
        guard status == .authorizedWhenInUse || status == .authorizedAlways else { return }
        isFindingLocation = true
        defer { isFindingLocation = false }
        guard let coordinate = await LocationProvider.currentCoordinate(timeout: .seconds(10)),
              spec.municipality.region.contains(coordinate) else { return }
        let address = await ReverseGeocoder.address(for: coordinate.clLocation)
        // The user may have placed a pin meanwhile; theirs wins.
        guard draft.coordinate == nil, !isLocationPickerPresented else { return }
        draft.coordinate = coordinate
        draft.locationText = address ?? ""
    }

    // MARK: Photos

    func addPhotos(_ images: [UIImage]) {
        let room = Self.maxPhotos - photos.count
        guard room > 0 else { return }
        let added = Array(images.prefix(room))
        photos.append(contentsOf: added)
        if persists {
            photoFiles.append(contentsOf: added.compactMap { DraftStore.writePhoto($0) })
        }
        recomposePhoto()
    }

    func removePhoto(at index: Int) {
        guard photos.indices.contains(index) else { return }
        photos.remove(at: index)
        if photoFiles.indices.contains(index) {
            DraftStore.deletePhoto(photoFiles.remove(at: index))
        }
        recomposePhoto()
    }

    private func recomposePhoto() {
        draft.photoJPEG = PhotoCollage.combine(photos)
    }

    // MARK: Draft persistence

    private var draftHasContent: Bool {
        !draftStorage.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !photos.isEmpty
    }

    private func scheduleDraftSave() {
        guard persists else { return }
        draftSaveTask?.cancel()
        draftSaveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            self?.saveDraftNow()
        }
    }

    /// Keeps an unsent draft with text or photos; an empty one is cleared. A sent one is left alone
    /// (`send` already cleared it).
    func saveDraftNow() {
        guard persists else { return }
        draftSaveTask?.cancel()
        guard sent == nil else { return }
        if draftHasContent {
            DraftStore.save(draftStorage, photoFiles: photoFiles)
        } else {
            DraftStore.clear()
        }
    }

    private func clearSavedDraft() {
        draftSaveTask?.cancel()
        photoFiles = []
        if persists {
            DraftStore.clear()
        }
    }

    /// Reopens an unsent report from before the app was closed.
    private func restoreDraft() {
        guard let saved = DraftStore.load() else { return }
        var restored = saved.draft
        restored.adapterID = spec?.id ?? Self.adapterID
        restored.contact = restored.wantsFeedback ? profileStorage : Contact()
        draftStorage = restored
        photos = saved.photos
        photoFiles = saved.photoFiles
        draftStorage.photoJPEG = PhotoCollage.combine(photos)
        guard draftHasContent else {
            clearSavedDraft()
            draftStorage = freshDraft()
            photos = []
            return
        }
        path = [.report]
    }

    /// Writes everything pending at once, e.g. when the app goes to the background.
    func persistNow() {
        saveProfileNow()
        saveDraftNow()
    }

    // MARK: Profile

    /// Email and phone problems in `contact`, judged exactly as the report judges them.
    func contactIssues(_ contact: Contact) -> [ValidationIssue] {
        guard let spec else { return [] }
        let probe = ReportDraft(adapterID: spec.id, wantsFeedback: false, contact: contact)
        return ReportValidator.validate(probe, spec: spec).filter { $0.field == .email || $0.field == .phone }
    }

    /// The saved profile has a non-empty e-mail the report accepts.
    var profileHasEmail: Bool {
        !profileStorage.email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !contactIssues(profileStorage).contains { $0.field == .email }
    }

    /// The profile can stand in for the reply fields: usable e-mail and no other problems.
    var profileIsReady: Bool {
        profileHasEmail && contactIssues(profileStorage).isEmpty
    }

    var profileIsEmpty: Bool { profileStorage == Contact() }

    private func scheduleProfileSave() {
        guard persists else { return }
        profileSaveTask?.cancel()
        profileSaveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            self?.saveProfileNow()
        }
    }

    func saveProfileNow() {
        guard persists else { return }
        profileSaveTask?.cancel()
        if profileIsEmpty || !rememberDetails {
            UserDefaults.standard.removeObject(forKey: Self.contactKey)
        } else if let data = try? JSONEncoder().encode(profileStorage) {
            UserDefaults.standard.set(data, forKey: Self.contactKey)
        }
    }

    /// Removes the saved details from this phone and turns replies off for the current report.
    func clearProfile() {
        profile = Contact()
        draft.wantsFeedback = false
        saveProfileNow()
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
        profileStorage = DemoData.profile
        var demo = DemoData.draft(adapterID: spec?.id ?? Self.adapterID)
        demo.categoryID = spec?.tile(id: demo.tileID)?.categoryID
        draft = demo
        if let image = DemoData.photo {
            photos = [image]
        }
        recomposePhoto()
        history.replaceAll(options.emptyHistory ? [] : DemoData.historyItems())
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
        profileStorage = Contact(firstName: "", lastName: "", phone: "", email: "test@test.se")
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
        case .settings:
            path = [.settings]
        case .contact:
            path = [.settings, .contactDetails]
        case .textsize:
            path = [.settings, .textSize]
        case .language:
            path = [.settings, .language]
        case .privacy:
            path = [.settings, .privacy]
        case .onboarding:
            path = []
        }
    }
}
