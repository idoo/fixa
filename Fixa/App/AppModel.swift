import BackgroundTasks
import CoreLocation
import FixaKit
import Foundation
import Network
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
    /// Reports the user sent that the e-service hasn't confirmed: waiting, may-have-been-sent, not sent.
    let outbox: OutboxStore
    /// True from the moment Send is accepted until its outcome is handled. The model-level guard
    /// against a double Send, independent of how the button looks.
    private(set) var isSendingDraft = false
    /// Outbox reports being sent right now; each id is sent by at most one call at a time.
    private(set) var sendingIDs: Set<UUID> = []
    /// A send `SendGuard` stopped: a repeat of a recent report (asks first) or one over the
    /// hourly/daily cap (blocks). `RootView` shows it as an alert.
    var sendGuardAlert: SendGuardAlert?
    /// Backing store of `sentRecords`.
    @ObservationIgnored private var guardRecords: [SentRecord] = []
    /// Last thing `NWPathMonitor` said; true until it has spoken.
    private(set) var isOnline = true
    @ObservationIgnored private var pathMonitor: NWPathMonitor?
    @ObservationIgnored private var lastPathOnline: Bool?
    @ObservationIgnored private var retryTask: Task<Void, Never>?
    @ObservationIgnored private var activeObserver: (any NSObjectProtocol)?
    /// The one outbox flush running now. Every trigger (launch, foreground, connectivity, back-off
    /// timer, background task) joins it instead of starting a second loop.
    @ObservationIgnored private var flushTask: Task<Void, Never>?
    /// A trigger arrived during the running flush: one more pass when it ends.
    @ObservationIgnored private var flushAgain = false
    @ObservationIgnored private var flushAgainIgnoringBackoff = false
    /// iOS is ending the background task: let the send in flight finish, start no new one.
    @ObservationIgnored var stopsOutboxAfterCurrentSend = false

    enum SendGuardAlert: Equatable {
        case duplicate(previous: Date)
        case tooMany(retryAfter: Date)
    }

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
    /// Switches the UI at once through `L10n`; `RootView` redraws on `effectiveLanguage`.
    var language: AppLanguage? {
        didSet {
            guard language != oldValue else { return }
            L10n.apply(language, savesSystemSetting: persists)
            guard persists else { return }
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
        outbox = OutboxStore(inMemory: options.demo || options.liveTest)
        profileStorage = Self.loadContact()
        var savedDisplay = DisplaySettings.load()
        if let size = options.textSize {
            savedDisplay.textSize = size
        }
        display = savedDisplay
        rememberDetails = UserDefaults.standard.object(forKey: Self.rememberKey) as? Bool ?? true
        let savedLanguage = UserDefaults.standard.string(forKey: AppLanguage.storageKey).flatMap(AppLanguage.init(rawValue:))
        language = savedLanguage
        L10n.apply(savedLanguage, savesSystemSetting: !options.demo && !options.liveTest)
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
        if persists {
            loadGuardRecords()
            startOutbox()
        }
    }

    /// Drafts and the profile are written only for real use, never for demo or live-test launches.
    private var persists: Bool { !options.demo && !options.liveTest }

    // MARK: Flow

    /// Idempotent: a second tap on a tile (or two tiles at once) sets the same one-screen path, so
    /// only one Report screen is ever pushed.
    func startReport(tile: AdapterSpec.Tile) {
        if draft.tileID != tile.id {
            draft.tileID = tile.id
            draft.categoryID = tile.categoryID
        }
        // When the report was started; kept across edits and app restarts (saved with the draft).
        // A draft left untouched (no text, no photo) starts again now.
        if draft.createdAt == nil || !draftHasContent {
            draft.createdAt = .now
        }
        // Never wipe the state of a send still under way.
        if !submission.isSending {
            submission.reset()
        }
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

    /// Sends the current draft. One at a time: a second call while one is in flight returns at once,
    /// whatever the button looks like, and a draft already on its receipt is never sent again.
    /// Waits for the e-service's final answer. A failure that is safe to retry keeps the report as
    /// "waiting to send"; an `.uncertain` one is recorded as "may have been sent" and never retried.
    /// `SendGuard` may stop it first: `sendGuardAlert` then asks (repeat) or explains (too many).
    func send() async {
        await send(confirmedDuplicate: false)
    }

    /// "Send anyway" on the repeat warning. The hourly/daily cap still applies.
    func sendAnyway() async {
        sendGuardAlert = nil
        await send(confirmedDuplicate: true)
    }

    private func send(confirmedDuplicate: Bool) async {
        // Demo seeds a receipt up front; everywhere else a set `sent` means this draft already went.
        guard let spec, !isSendingDraft, options.demo || sent == nil else { return }
        isSendingDraft = true
        defer { isSendingDraft = false }
        if options.demo {
            // "-FixaDemo: no network". Nothing leaves the phone; history is in memory only.
            sent = DemoData.receipt
            let item = historyItem(id: UUID(), date: .now, caseNumber: DemoData.receipt.caseNumber, status: .sent)
            history.add(item)
            sent?.historyID = item.id
            path.append(.receipt)
            return
        }
        let dryRun = options.dryRun
        if !dryRun {
            switch sendGuardDecision(for: draft, checksDuplicate: !confirmedDuplicate) {
            case .ok:
                break
            case .duplicate(let previous):
                sendGuardAlert = .duplicate(previous: previous)
                return
            case .tooMany(let retryAfter):
                sendGuardAlert = .tooMany(retryAfter: retryAfter)
                return
            }
        }
        var result = await submission.submit(draft, spec: spec, dryRun: dryRun, recordResponses: options.liveTest)
        // The form changed: drift stops before the final step, so nothing reached the municipality.
        // Try once more with a newer signed adapter if there is one; otherwise Review shows the drift.
        if result == nil, case .formChanged? = submission.error,
           await adapters.refreshAfterFormChange(), let fresh = self.spec {
            submission.reset()
            result = await submission.submit(draft, spec: fresh, dryRun: dryRun, recordResponses: options.liveTest)
        }
        guard let result else {
            if let error = submission.error, persists, !dryRun {
                keepUnconfirmed(after: error)
            }
            return
        }
        sent = result
        if !result.isDryRun {
            recordSend(draft, date: result.date)
            let item = historyItem(id: UUID(), date: result.date, caseNumber: result.caseNumber, status: .sent)
            history.add(item)
            sent?.historyID = item.id
            clearSavedDraft()
        }
        path.append(.receipt)
    }

    /// The send failed in a way that may still end well: the report moves from the draft into the
    /// outbox (with its photo and reply details) and Sent reports, and the receipt explains what next.
    private func keepUnconfirmed(after error: SubmissionError) {
        let status: HistoryItem.Status
        if error.isRetrySafe {
            status = .waiting
        } else if case .uncertain = error {
            status = .maybeSent
        } else {
            // Form changed, broken adapter, rejected by the e-service: Review shows it and offers e-mail.
            return
        }
        let now = Date.now
        if status == .maybeSent {
            // It may have reached the municipality: counts for the repeat warning and the cap.
            recordSend(draft, date: now)
        }
        let id = UUID()
        let pending = PendingReport(
            id: id,
            draft: draft,
            createdAt: now,
            attempts: 1,
            nextAttemptAt: Self.nextAttemptDate(afterAttempts: 1, error: error, now: now),
            held: status != .waiting
        )
        // Keep the draft if the report can't be stored: Review's error and "Try again" stay.
        guard outbox.put(pending) else { return }
        history.add(historyItem(id: id, date: now, caseNumber: nil, status: status))
        sent = SentReport(caseNumber: nil, date: now, isDryRun: false, outcome: status == .waiting ? .waiting : .maybeSent, historyID: id)
        clearSavedDraft()
        submission.reset()
        path.append(.receipt)
        scheduleRetry()
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
    /// Reports still waiting, possibly sent or not sent stay listed: they are not done yet.
    func clearHistory() {
        let unconfirmed = history.items.filter { $0.status != .sent }
        if unconfirmed.isEmpty {
            history.deleteAll()
        } else {
            history.delete(Set(history.items.filter { $0.status == .sent }.map(\.id)))
        }
    }

    /// Removes reports from Sent reports. One that hasn't been confirmed leaves the outbox too, so
    /// it is no longer sent on its own. Not while that report is being sent.
    func removeReports(_ ids: Set<UUID>) {
        let removable = ids.subtracting(sendingIDs)
        outbox.remove(removable)
        history.delete(removable)
    }

    /// Any send in flight, the user's own or from the outbox.
    var isBusySending: Bool { isSendingDraft || !sendingIDs.isEmpty || submission.isSending }

    /// Contact details, the unsent report with its photos, reports waiting to be sent and the
    /// sent-reports list leave this phone. Language and display settings stay. Not while a report
    /// is being sent.
    func deleteAllData() {
        guard !isBusySending else { return }
        profileSaveTask?.cancel()
        draftSaveTask?.cancel()
        retryTask?.cancel()
        profileStorage = Contact()
        photos = []
        photoFiles = []
        if persists {
            UserDefaults.standard.removeObject(forKey: Self.contactKey)
            DraftStore.clear()
            BackgroundOutbox.schedule(earliest: nil)
            UserDefaults.standard.removeObject(forKey: Self.sentRecordsKey)
        }
        draftStorage = freshDraft()
        showIssues = false
        outbox.deleteAll()
        guardRecords = []
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

    private func historyItem(id: UUID, date: Date, caseNumber: String?, status: HistoryItem.Status) -> HistoryItem {
        HistoryItem(
            id: id,
            date: date,
            tileID: draft.tileID,
            description: draft.description,
            locationText: draft.locationText,
            latitude: draft.coordinate?.latitude,
            longitude: draft.coordinate?.longitude,
            caseNumber: caseNumber,
            thumbnail: draft.photoJPEG.flatMap { PhotoCollage.thumbnail(from: $0) },
            status: status
        )
    }

    // MARK: Outbox

    /// Sends tried in all before Fixa stops and asks the user, the user's own first Send included.
    static let maxAutomaticAttempts = 5

    /// Wait before the next automatic try after `attempts` tries; a connectivity change may try sooner.
    static func retryDelay(afterAttempts attempts: Int) -> TimeInterval {
        switch attempts {
        case ...1: 60
        case 2: 5 * 60
        case 3: 15 * 60
        default: 60 * 60
        }
    }

    /// The back-off, or the e-service's own `Retry-After` when it asks for longer (capped at a day).
    static func nextAttemptDate(afterAttempts attempts: Int, error: SubmissionError, now: Date) -> Date {
        let asked = min(error.retryAfter ?? 0, 24 * 60 * 60)
        return now.addingTimeInterval(max(retryDelay(afterAttempts: attempts), asked))
    }

    // MARK: Send guard

    /// Reports that reached, or may have reached, the municipality in the last 48 hours, for
    /// `SendGuard`. Kept apart from Sent reports (UserDefaults `fixa.sentRecords`) so clearing that
    /// list doesn't lift the guard; "Delete all data" removes them too.
    var sentRecords: [SentRecord] {
        let cutoff = Date.now.addingTimeInterval(-Self.sentRecordLifetime)
        return guardRecords.filter { $0.date > cutoff }
    }

    private static let sentRecordsKey = "fixa.sentRecords"
    /// The longest window `SendGuard` looks back over.
    private static let sentRecordLifetime = max(SendGuard.duplicateWindow, SendGuard.limits.map { $0.window }.max() ?? 0)

    /// A send whose final step went out: a receipt, or no answer (may have been sent).
    private func recordSend(_ draft: ReportDraft, date: Date) {
        guardRecords = sentRecords + [SentRecord(draft, date: date)]
        saveGuardRecords()
    }

    private func saveGuardRecords() {
        guard persists else { return }
        if let data = try? JSONEncoder().encode(guardRecords) {
            UserDefaults.standard.set(data, forKey: Self.sentRecordsKey)
        }
    }

    /// Saved records; on the first launch with the guard, seeded from Sent reports.
    private func loadGuardRecords() {
        guard persists else { return }
        if let data = UserDefaults.standard.data(forKey: Self.sentRecordsKey) {
            guardRecords = (try? JSONDecoder().decode([SentRecord].self, from: data)) ?? []
            return
        }
        guardRecords = history.items
            .filter { $0.status == .sent || $0.status == .maybeSent }
            .map { item in
                var coordinate: Coordinate?
                if let latitude = item.latitude, let longitude = item.longitude {
                    coordinate = Coordinate(latitude: latitude, longitude: longitude)
                }
                return SentRecord(date: item.date, tileID: item.tileID, coordinate: coordinate, locationText: item.locationText)
            }
        guardRecords = sentRecords
        saveGuardRecords()
    }

    /// `checksDuplicate: false` is for a send the user already confirmed (an outbox retry, "Send
    /// anyway"): without a place it matches no earlier report, so only the rate limit can answer.
    private func sendGuardDecision(for draft: ReportDraft, checksDuplicate: Bool) -> SendGuard.Decision {
        var probe = draft
        if !checksDuplicate {
            probe.coordinate = nil
            probe.locationText = ""
        }
        return SendGuard.check(probe, history: sentRecords, now: .now)
    }

    /// For Home: reports Fixa still sends on its own, or that stopped and need the user.
    /// Reports that may have been sent are left to the receipt and Sent reports.
    struct OutboxNotice: Equatable {
        var title: String
        var message: String
    }

    var outboxNotice: OutboxNotice? {
        if history.items.contains(where: { $0.status == .notSent }) {
            return OutboxNotice(
                title: String(localized: "Not sent yet", bundle: L10n.bundle, locale: L10n.locale),
                message: String(localized: "Fixa couldn't send a report. Open Sent reports to try again.", bundle: L10n.bundle, locale: L10n.locale)
            )
        }
        guard history.items.contains(where: { $0.status == .waiting }) else { return nil }
        return OutboxNotice(
            title: String(localized: "Waiting to send", bundle: L10n.bundle, locale: L10n.locale),
            message: isOnline
                ? String(localized: "Your report is saved on this phone. Fixa tries again in a little while, also in the background.", bundle: L10n.bundle, locale: L10n.locale)
                : String(localized: "Your report is saved on this phone. Fixa sends it when you're back online, also in the background.", bundle: L10n.bundle, locale: L10n.locale)
        )
    }

    /// The report as plain text for e-mail, as Review's "Copy report text" gives it; nil once it is gone.
    func reportText(for id: UUID) -> String? {
        guard let spec, let draft = outbox.item(id: id)?.draft else { return nil }
        var text = MailFallback.body(draft, spec: spec)
        if let email = spec.fallbackEmail {
            text = String(localized: "To: \(email)", bundle: L10n.bundle, locale: L10n.locale) + "\n"
                + String(localized: "Subject: \(MailFallback.subject(draft, spec: spec))", bundle: L10n.bundle, locale: L10n.locale) + "\n\n" + text
        }
        return text
    }

    /// Whether a waiting or unconfirmed report asked for a reply by e-mail (and so gets a confirmation).
    func wantsReply(_ id: UUID) -> Bool {
        outbox.item(id: id)?.draft.wantsFeedback ?? false
    }

    /// The user's explicit "Try again" on a report Fixa stopped sending, or a confirmed
    /// "Send again anyway" on one that may have arrived. Restarts the automatic tries.
    /// Already confirmed, so no repeat warning, but the hourly/daily cap still applies.
    func sendNow(_ id: UUID) async {
        guard var item = outbox.item(id: id), !sendingIDs.contains(id) else { return }
        if options.demo {
            // No network in demo: pretend it went through.
            outbox.remove([id])
            markSent(id, caseNumber: DemoData.receipt.caseNumber, date: .now)
            return
        }
        if case .tooMany(let retryAfter) = sendGuardDecision(for: item.draft, checksDuplicate: false) {
            sendGuardAlert = .tooMany(retryAfter: retryAfter)
            return
        }
        item.held = false
        item.attempts = 0
        outbox.put(item)
        await attempt(id, automatic: false)
        scheduleRetry()
    }

    private func startOutbox() {
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { @Sendable [weak self] path in
            let online = path.status == .satisfied
            Task { @MainActor [weak self] in self?.connectivityChanged(online: online) }
        }
        monitor.start(queue: DispatchQueue(label: "se.fixa.outbox.path"))
        pathMonitor = monitor
        activeObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { @Sendable [weak self] _ in
            Task { @MainActor [weak self] in
                self?.stopsOutboxAfterCurrentSend = false
                await self?.flushOutbox(ignoringBackoff: false)
            }
        }
        scheduleRetry()
    }

    /// The first path update after launch counts as a change, so launch tries once too.
    private func connectivityChanged(online: Bool) {
        isOnline = online
        let changed = lastPathOnline != online
        lastPathOnline = online
        guard changed, online else { return }
        Task { await flushOutbox(ignoringBackoff: true) }
    }

    /// Single flight: if a flush is already running, this asks it for one more pass and waits for
    /// it, so foreground, connectivity, timer and background task firing together run one loop.
    /// Returns when the outbox has had its try.
    private func flushOutbox(ignoringBackoff: Bool) async {
        guard persists else { return }
        if let running = flushTask {
            flushAgain = true
            flushAgainIgnoringBackoff = flushAgainIgnoringBackoff || ignoringBackoff
            await running.value
            return
        }
        // Main-actor task: set before it can start, cleared by itself before it ends.
        let task = Task { [self] in
            var ignoring = ignoringBackoff
            repeat {
                flushAgain = false
                flushAgainIgnoringBackoff = false
                await flushPass(ignoringBackoff: ignoring)
                ignoring = flushAgainIgnoringBackoff
            } while flushAgain && !stopsOutboxAfterCurrentSend
            flushTask = nil
            scheduleRetry()
        }
        flushTask = task
        await task.value
    }

    /// One try for each waiting report: all of them on a connectivity change, otherwise those
    /// whose back-off has passed. Never touches held reports (may have been sent, not sent).
    private func flushPass(ignoringBackoff: Bool) async {
        guard lastPathOnline == true else { return }
        let now = Date.now
        let due = outbox.items.filter { !$0.held && (ignoringBackoff || $0.nextAttemptAt <= now) }.map(\.id)
        for id in due {
            guard lastPathOnline == true, !stopsOutboxAfterCurrentSend else { break }
            await attempt(id, automatic: true, ignoringBackoff: ignoringBackoff)
        }
    }

    /// The background task's entry: waits briefly for the first connectivity answer of a fresh
    /// background launch, then one flush that honours the back-off.
    func drainOutboxInBackground() async {
        guard persists else { return }
        stopsOutboxAfterCurrentSend = false
        var waited = 0
        while lastPathOnline == nil, waited < 50 {
            try? await Task.sleep(for: .milliseconds(100))
            waited += 1
        }
        await flushOutbox(ignoringBackoff: false)
    }

    /// Sends one outbox report and waits for the e-service's final answer. Single flight per id:
    /// the check and the insert into `sendingIDs` run on the main actor with no await between.
    private func attempt(_ id: UUID, automatic: Bool, ignoringBackoff: Bool = true) async {
        guard persists, let spec, var item = outbox.item(id: id), !sendingIDs.contains(id) else { return }
        if automatic, item.held || item.attempts >= Self.maxAutomaticAttempts { return }
        // Re-read: another trigger may have tried it since this pass picked it.
        if automatic, !ignoringBackoff, item.nextAttemptAt > .now { return }
        // Rate limit counts retries too; waiting for it is not a failed try.
        if case .tooMany(let retryAfter) = sendGuardDecision(for: item.draft, checksDuplicate: false) {
            item.nextAttemptAt = max(item.nextAttemptAt, retryAfter)
            outbox.put(item)
            return
        }
        sendingIDs.insert(id)
        defer { sendingIDs.remove(id) }
        let service = SubmissionService()
        var result = await service.submit(item.draft, spec: spec, dryRun: false)
        // Form drift stops before the final step: once more with a newer signed adapter, if any.
        if result == nil, case .formChanged? = service.error,
           await adapters.refreshAfterFormChange(), let fresh = self.spec {
            service.reset()
            result = await service.submit(item.draft, spec: fresh, dryRun: false)
        }
        if let result {
            recordSend(item.draft, date: result.date)
            outbox.remove([id])
            markSent(id, caseNumber: result.caseNumber, date: result.date)
            return
        }
        // Cancelled: nothing is known, so nothing changes.
        guard let error = service.error else { return }
        item.attempts += 1
        let status: HistoryItem.Status
        if error.isRetrySafe, item.attempts < Self.maxAutomaticAttempts {
            item.nextAttemptAt = Self.nextAttemptDate(afterAttempts: item.attempts, error: error, now: .now)
            status = .waiting
        } else if case .uncertain = error {
            // Never sent again on its own; counts as a send for the guard.
            recordSend(item.draft, date: .now)
            item.held = true
            status = .maybeSent
        } else {
            // Tries ran out, or retrying can't help (form changed, rejected): the user decides.
            item.held = true
            status = .notSent
        }
        outbox.put(item)
        history.update(id: id) { $0.status = status }
        if sent?.historyID == id {
            sent?.outcome = status == .maybeSent ? .maybeSent : .waiting
        }
    }

    private func markSent(_ id: UUID, caseNumber: String?, date: Date) {
        history.update(id: id) {
            $0.status = .sent
            $0.caseNumber = caseNumber
            $0.date = date
        }
        if sent?.historyID == id {
            sent = SentReport(caseNumber: caseNumber, date: date, isDryRun: false, outcome: .sent, historyID: id)
        }
    }

    /// Wakes for the earliest back-off while the app runs, and asks iOS for a background task at
    /// the same time for when it doesn't. The flush runs in its own task so rescheduling never
    /// cancels a send already under way. Called whenever a report is queued or a back-off is set.
    private func scheduleRetry() {
        retryTask?.cancel()
        guard persists else { return }
        let next = outbox.items.filter { !$0.held }.map(\.nextAttemptAt).min()
        BackgroundOutbox.schedule(earliest: next)
        guard let next else { return }
        retryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(max(1, next.timeIntervalSinceNow)))
            guard !Task.isCancelled else { return }
            Task { @MainActor [weak self] in await self?.flushOutbox(ignoringBackoff: false) }
        }
    }

    /// When the app leaves the screen: makes sure iOS knows about waiting reports.
    func scheduleBackgroundSend() {
        guard persists else { return }
        BackgroundOutbox.schedule(earliest: outbox.items.filter { !$0.held }.map(\.nextAttemptAt).min())
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
        switch options.sendState {
        case .offline?:
            seedDemoUnconfirmed(.waiting)
        case .uncertain?:
            seedDemoUnconfirmed(.maybeSent)
        case nil:
            sent = DemoData.receipt
        }
    }

    /// `-FixaStatus offline|uncertain` with `-FixaDemo 1`: the demo report as waiting to send or
    /// maybe sent, on the receipt, in Sent reports and (waiting) on Home. In memory only.
    private func seedDemoUnconfirmed(_ status: HistoryItem.Status) {
        let id = UUID()
        let now = Date.now.addingTimeInterval(-4 * 60)
        outbox.put(PendingReport(id: id, draft: draft, createdAt: now, attempts: 1, nextAttemptAt: now, held: status != .waiting))
        history.add(historyItem(id: id, date: now, caseNumber: nil, status: status))
        sent = SentReport(caseNumber: nil, date: now, isDryRun: false, outcome: status == .waiting ? .waiting : .maybeSent, historyID: id)
        isOnline = status != .waiting
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

/// Sends waiting outbox reports while Fixa is not on screen. Two requests for the same work: a
/// processing task that needs a network and an app refresh, whichever iOS grants first; both run
/// `AppModel.drainOutboxInBackground`, which is single flight and honours the back-off. Held
/// reports (may have been sent, not sent) are never touched. A force-quit app gets neither.
enum BackgroundOutbox {
    static let processingID = "se.jvcr.fixa.outbox"
    static let refreshID = "se.jvcr.fixa.outbox.refresh"

    private static var permitted: Set<String> {
        Set(Bundle.main.object(forInfoDictionaryKey: "BGTaskSchedulerPermittedIdentifiers") as? [String] ?? [])
    }

    /// Must run before launch finishes (`FixaApp.init`). Only identifiers the Info.plist permits:
    /// registering any other one is a crash.
    @MainActor
    static func register(_ model: AppModel) {
        let allowed = permitted
        for id in [processingID, refreshID] where allowed.contains(id) {
            BGTaskScheduler.shared.register(forTaskWithIdentifier: id, using: .main) { task in
                nonisolated(unsafe) let task = task
                MainActor.assumeIsolated { run(task, model: model) }
            }
        }
    }

    /// `earliest` nil: nothing waiting, so no request stays pending.
    @MainActor
    static func schedule(earliest: Date?) {
        let allowed = permitted
        guard let earliest else {
            BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: processingID)
            BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: refreshID)
            return
        }
        if allowed.contains(processingID) {
            let request = BGProcessingTaskRequest(identifier: processingID)
            request.requiresNetworkConnectivity = true
            request.requiresExternalPower = false
            request.earliestBeginDate = earliest
            try? BGTaskScheduler.shared.submit(request)
        }
        if allowed.contains(refreshID) {
            let request = BGAppRefreshTaskRequest(identifier: refreshID)
            request.earliestBeginDate = earliest
            try? BGTaskScheduler.shared.submit(request)
        }
    }

    /// On expiry the send in flight is never cancelled (that could leave a case Fixa can't see);
    /// it finishes under its own `beginBackgroundTask` time and no further report starts.
    @MainActor
    private static func run(_ task: BGTask, model: AppModel) {
        let completion = Completion(task)
        task.expirationHandler = {
            Task { @MainActor in
                model.stopsOutboxAfterCurrentSend = true
                completion.finish(success: false)
            }
        }
        Task { @MainActor in
            await model.drainOutboxInBackground()
            completion.finish(success: true)
        }
    }

    /// `setTaskCompleted` exactly once, whichever of expiry and the drain comes first.
    @MainActor
    private final class Completion {
        nonisolated(unsafe) private let task: BGTask
        private var done = false

        init(_ task: BGTask) {
            self.task = task
        }

        func finish(success: Bool) {
            guard !done else { return }
            done = true
            task.setTaskCompleted(success: success)
        }
    }
}
