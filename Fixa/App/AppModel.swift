import BackgroundTasks
import CoreLocation
import FixaKit
import Foundation
import Network
import Observation
import UIKit
import UniformTypeIdentifiers

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
    /// The random wait after the network comes back, so phones don't all send at the same second.
    @ObservationIgnored private var reconnectTask: Task<Void, Never>?
    /// iOS is ending the background task: let the send in flight finish, start no new one.
    @ObservationIgnored var stopsOutboxAfterCurrentSend = false
    /// The repeat the user confirmed with "Send anyway"; written into the report as an earlier one.
    @ObservationIgnored private var duplicateOf: PreviousReport?

    enum SendGuardAlert: Equatable {
        case duplicate(previous: Date, caseNumber: String?)
        case tooMany(retryAfter: Date)
    }

    /// Why Fixa sends nothing on its own right now: the e-service refused Fixa (401/403), asked
    /// for a login, or the status file says it is down. Saved (UserDefaults `fixa.sendsPaused`);
    /// cleared by a send the user started that goes through, or by the status file saying ok.
    enum SendsPause: String, Codable, Sendable {
        case blocked, loginRequired, serviceDown
    }

    private(set) var sendsPaused: SendsPause?
    /// The other kommun the pin is in (reverse geocoding, else the adapter's box); nil when the
    /// pin is inside, unknown or missing. Review is not allowed while it is set.
    private(set) var outsideMunicipalityName: String?
    @ObservationIgnored private var municipalityTask: Task<Void, Never>?
    /// The pin came from the automatic prefill and the user hasn't moved or confirmed it.
    var pinIsAutomatic = false
    /// The place text was typed by the resident, not filled in from the pin's address.
    var placeTextIsTyped = false

    var path: [Route] = []
    /// What the report sends. `contact` always mirrors the profile while a reply is wanted and is
    /// empty otherwise, so turning the toggle off never sends (or deletes) the saved details.
    var draft: ReportDraft {
        get { draftStorage }
        set {
            var next = newValue
            next.contact = next.wantsFeedback ? profileStorage : Contact()
            // A translated place belongs to the text it was made from.
            if next.locationText != draftStorage.locationText, next.translation?.locationText != nil {
                next.translation?.locationText = nil
            }
            let pinMoved = next.coordinate != draftStorage.coordinate
            draftStorage = next
            if pinMoved {
                pinIsAutomatic = false
                checkMunicipality()
            }
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
    static let adapterID = "se.varmdo.ksb"
    private static let contactKey = "fixa.contact"
    private static let rememberKey = "fixa.rememberDetails"
    private static let onboardedKey = "fixa.onboarded"
    private static let sendsPausedKey = "fixa.sendsPaused"

    init(options: LaunchOptions = .current) {
        self.options = options
        history = HistoryStore(inMemory: options.demo)
        outbox = OutboxStore(inMemory: options.demo)
        profileStorage = Self.loadContact()
        var savedDisplay = DisplaySettings.load()
        if let size = options.textSize {
            savedDisplay.textSize = size
        }
        display = savedDisplay
        rememberDetails = UserDefaults.standard.object(forKey: Self.rememberKey) as? Bool ?? true
        let savedLanguage = UserDefaults.standard.string(forKey: AppLanguage.storageKey).flatMap(AppLanguage.init(rawValue:))
        language = savedLanguage
        L10n.apply(savedLanguage, savesSystemSetting: !options.demo)
        // Demo and screenshot launches skip it unless they ask for `-FixaScreen onboarding`.
        if options.screen == .onboarding {
            isOnboardingPresented = true
        } else if options.demo || options.screen != nil {
            isOnboardingPresented = false
        } else {
            isOnboardingPresented = !UserDefaults.standard.bool(forKey: Self.onboardedKey)
        }
        draftStorage = ReportDraft(adapterID: adapters.spec?.id ?? Self.adapterID)
        draftStorage = freshDraft()
        if persists {
            sendsPaused = UserDefaults.standard.string(forKey: Self.sendsPausedKey).flatMap(SendsPause.init(rawValue:))
            loadGuardRecords()
            // Before the draft comes back: a draft whose send was cut off must not reopen.
            settleInterruptedSends()
            syncSendsPauseWithStatus()
        }
        if options.demo {
            seedDemo()
        } else if options.screen == nil {
            restoreDraft()
        }
        if let screen = options.screen {
            open(screen)
        }
        if persists {
            startOutbox()
        }
    }

    /// Drafts and the profile are written only for real use, never for demo launches.
    private var persists: Bool { !options.demo }

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
        guard issues.isEmpty, outsideMunicipalityName == nil else { return false }
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
        if let duplicateOf {
            draft.previousReport = duplicateOf
        }
        duplicateOf = nil
        await send(confirmedDuplicate: true)
    }

    private func send(confirmedDuplicate: Bool) async {
        // Demo seeds a receipt up front; everywhere else a set `sent` means this draft already went.
        guard let spec, !isSendingDraft, options.demo || sent == nil, outsideMunicipalityName == nil else { return }
        isSendingDraft = true
        defer { isSendingDraft = false }
        if options.demo {
            // "-FixaDemo: no network". Nothing leaves the phone; history is in memory only.
            sent = DemoData.receipt
            var item = historyItem(id: UUID(), from: draft, date: .now, caseNumber: DemoData.receipt.caseNumber, status: .sent)
            item.kommunMessage = DemoData.receipt.kommunMessage
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
            case .duplicate(let previous, let caseNumber):
                duplicateOf = PreviousReport(caseNumber: caseNumber, date: previous)
                sendGuardAlert = .duplicate(previous: previous, caseNumber: caseNumber)
                return
            case .tooMany(let retryAfter):
                sendGuardAlert = .tooMany(retryAfter: retryAfter)
                return
            }
        }
        // The outbox id this report gets if its final step goes out (see `markFinalSend`).
        let id = UUID()
        let report = draft
        let mark: @Sendable () async -> Void
        if dryRun {
            mark = {}
        } else {
            mark = { @MainActor [weak self] in await self?.markFinalSend(id, draft: report) }
        }
        var result = await submission.submit(report, spec: spec, dryRun: dryRun, beforeFinalSend: mark)
        // The form changed: drift stops before the final step, so nothing reached the municipality.
        // Try once more with a newer signed adapter if there is one; otherwise Review shows the drift.
        if result == nil, case .formChanged? = submission.error,
           await refreshAdapterAfterFormChange(), let fresh = self.spec {
            submission.reset()
            result = await submission.submit(report, spec: fresh, dryRun: dryRun, beforeFinalSend: mark)
        }
        guard let result else {
            if persists, !dryRun, let error = submission.error ?? interruptedAfterFinalSend(id) {
                keepUnconfirmed(report, id: id, after: error)
            }
            return
        }
        sent = result
        if !result.isDryRun {
            setSendsPaused(nil)
            recordSend(report, date: result.date, caseNumber: result.caseNumber)
            outbox.remove([id])
            var item = historyItem(id: id, from: report, date: result.date, caseNumber: result.caseNumber, status: .sent)
            item.record(result)
            history.add(item)
            sent?.historyID = item.id
            clearSavedDraft()
        }
        path.append(.receipt)
    }

    /// The send ended with no error (cancelled) after its final step was marked: it may have gone.
    private func interruptedAfterFinalSend(_ id: UUID) -> SubmissionError? {
        outbox.item(id: id)?.finalSendAt != nil ? .uncertain("ended after the final step without an answer") : nil
    }

    /// The send failed in a way that may still end well: the report moves from the draft into the
    /// outbox (with its photo and reply details) and Sent reports, and the receipt explains what next.
    /// `id` is the outbox entry the final-step mark may already have written.
    private func keepUnconfirmed(_ report: ReportDraft, id: UUID, after error: SubmissionError) {
        pauseIfRefused(error)
        let status: HistoryItem.Status
        if error.isRetrySafe {
            status = .waiting
        } else if case .uncertain = error {
            status = .maybeSent
        } else {
            // Form changed, broken adapter, refused or rejected by the e-service: nothing was
            // filed. Review shows it and offers the kommun's website.
            outbox.remove([id])
            return
        }
        let now = Date.now
        if status == .maybeSent {
            // It may have reached the municipality: counts for the repeat warning and the cap.
            recordSend(report, date: now, caseNumber: nil)
        }
        let pending = PendingReport(
            id: id,
            draft: report,
            createdAt: now,
            attempts: 1,
            nextAttemptAt: Self.nextAttemptDate(afterAttempts: 1, error: error, now: now),
            held: status != .waiting,
            serverRetryAfter: Self.serverRetryAfter(error, now: now)
        )
        // Keep the draft if the report can't be stored: Review's error and "Try again" stay.
        guard outbox.put(pending) else { return }
        history.add(historyItem(id: id, from: report, date: now, caseNumber: nil, status: status))
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
        placeTextIsTyped = false
        duplicateOf = nil
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
    /// sent-reports list leave this phone. Language and display settings stay, and so do the
    /// `SendGuard` records (dates, tiles, places, case numbers): the repeat warning and the cap
    /// must not be lifted by deleting data. Not while a report is being sent.
    func deleteAllData() {
        guard !isBusySending else { return }
        profileSaveTask?.cancel()
        draftSaveTask?.cancel()
        retryTask?.cancel()
        reconnectTask?.cancel()
        profileStorage = Contact()
        photos = []
        photoFiles = []
        if persists {
            UserDefaults.standard.removeObject(forKey: Self.contactKey)
            DraftStore.clear()
            BackgroundOutbox.schedule(earliest: nil)
        }
        draftStorage = freshDraft()
        municipalityTask?.cancel()
        outsideMunicipalityName = nil
        pinIsAutomatic = false
        placeTextIsTyped = false
        duplicateOf = nil
        showIssues = false
        outbox.deleteAll()
        history.deleteAll()
        sent = nil
        submission.reset()
    }

    // MARK: Location

    /// A prefilled pin is only as good as this; anything vaguer waits for the user's own pin.
    static let prefillAccuracyMeters: CLLocationAccuracy = 50

    /// On a new report, fills in the current place and address when precise location is already
    /// allowed and the fix is within `prefillAccuracyMeters`. Never asks for permission: that
    /// prompt stays on the explicit "Use my location". Never places a pin in another kommun and
    /// never replaces a place the resident typed.
    func prefillLocationIfAllowed() async {
        guard persists, let spec, draft.coordinate == nil, !isFindingLocation else { return }
        let manager = CLLocationManager()
        guard manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways,
              manager.accuracyAuthorization == .fullAccuracy else { return }
        isFindingLocation = true
        defer { isFindingLocation = false }
        guard let fix = try? await LocationProvider.currentFix(timeout: .seconds(10), accuracy: Self.prefillAccuracyMeters),
              !fix.isApproximate, fix.horizontalAccuracy <= Self.prefillAccuracyMeters,
              spec.municipality.region.contains(fix.coordinate) else { return }
        let place = await ReverseGeocoder.place(for: fix.coordinate.clLocation)
        guard Self.otherMunicipality(place, spec: spec, coordinate: fix.coordinate) == nil else { return }
        // The user may have placed a pin meanwhile; theirs wins.
        guard draft.coordinate == nil, !isLocationPickerPresented else { return }
        draft.coordinate = fix.coordinate
        pinIsAutomatic = true
        if !placeTextIsTyped {
            draft.locationText = place?.address ?? ""
        }
    }

    /// Sets `outsideMunicipalityName` for the current pin: the adapter's box answers at once, the
    /// reverse-geocoded kommun when it arrives.
    private func checkMunicipality() {
        municipalityTask?.cancel()
        guard let spec, let coordinate = draftStorage.coordinate else {
            outsideMunicipalityName = nil
            return
        }
        outsideMunicipalityName = Self.otherMunicipality(nil, spec: spec, coordinate: coordinate)
        municipalityTask = Task { [weak self] in
            let place = await ReverseGeocoder.place(for: coordinate.clLocation)
            guard !Task.isCancelled, let self, self.draftStorage.coordinate == coordinate else { return }
            self.outsideMunicipalityName = Self.otherMunicipality(place, spec: spec, coordinate: coordinate)
        }
    }

    /// The other kommun `coordinate` lies in, or nil when it is inside or that is unknown.
    /// For Swedish places Apple returns the kommun as `subAdministrativeArea` ("Värmdö", "Nacka",
    /// "Vaxholm") and the town as `locality` ("Gustavsberg", "Saltsjö-Boo"), so a locality only
    /// ever confirms "inside". Without either, the adapter's box decides.
    static func otherMunicipality(_ place: ReverseGeocoder.Place?, spec: AdapterSpec, coordinate: Coordinate) -> String? {
        let names = Set(spec.municipality.geocoderNames.map(normalizedPlaceName))
        if let kommun = place?.kommun?.trimmingCharacters(in: .whitespacesAndNewlines), !kommun.isEmpty {
            return names.contains(normalizedPlaceName(kommun)) ? nil : kommun
        }
        if let locality = place?.locality, names.contains(normalizedPlaceName(locality)) {
            return nil
        }
        return spec.municipality.region.contains(coordinate)
            ? nil
            : String(localized: "another municipality", bundle: L10n.bundle, locale: L10n.locale)
    }

    private static func normalizedPlaceName(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "sv_SE"))
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

    var draftHasContent: Bool {
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
            DraftStore.save(draftStorage, photoFiles: photoFiles, pinIsAutomatic: pinIsAutomatic, placeTextIsTyped: placeTextIsTyped)
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
        pinIsAutomatic = saved.pinIsAutomatic
        placeTextIsTyped = saved.placeTextIsTyped
        checkMunicipality()
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

    private func historyItem(id: UUID, from report: ReportDraft, date: Date, caseNumber: String?, status: HistoryItem.Status) -> HistoryItem {
        HistoryItem(
            id: id,
            date: date,
            tileID: report.tileID,
            description: report.description,
            locationText: report.locationText,
            latitude: report.coordinate?.latitude,
            longitude: report.coordinate?.longitude,
            caseNumber: caseNumber,
            thumbnail: report.photoJPEG.flatMap { PhotoCollage.thumbnail(from: $0) },
            status: status,
            filedText: spec.map { ReportComposer.filedText(for: report, spec: $0, now: date) }
        )
    }

    // MARK: Outbox

    /// Sends tried in all before Fixa stops and asks the user, the user's own first Send included.
    static let maxAutomaticAttempts = 5

    /// Wait before the next automatic try after `attempts` tries (before jitter). Every automatic
    /// trigger honours it; only the user's own "Try again" may go sooner.
    static func retryDelay(afterAttempts attempts: Int) -> TimeInterval {
        switch attempts {
        case ...1: 60
        case 2: 5 * 60
        case 3: 15 * 60
        default: 60 * 60
        }
    }

    /// The back-off with ±20% random jitter, or the e-service's own `Retry-After` when it asks for
    /// longer (capped at a day).
    static func nextAttemptDate(afterAttempts attempts: Int, error: SubmissionError, now: Date) -> Date {
        let jittered = retryDelay(afterAttempts: attempts) * Double.random(in: 0.8...1.2)
        let asked = min(error.retryAfter ?? 0, 24 * 60 * 60)
        return now.addingTimeInterval(max(jittered, asked))
    }

    /// When the e-service's `Retry-After` ends, if it sent one (capped at a day).
    static func serverRetryAfter(_ error: SubmissionError, now: Date) -> Date? {
        error.retryAfter.map { now.addingTimeInterval(min($0, 24 * 60 * 60)) }
    }

    /// Longest random wait after the network comes back before the outbox is tried.
    static let reconnectSpread: TimeInterval = 60

    // MARK: Send guard

    /// Reports that reached, or may have reached, the municipality within the longest `SendGuard`
    /// window. Kept apart from Sent reports (UserDefaults `fixa.sentRecords`) so neither clearing
    /// that list nor "Delete all data" lifts the guard.
    var sentRecords: [SentRecord] {
        let cutoff = Date.now.addingTimeInterval(-Self.sentRecordLifetime)
        return guardRecords.filter { $0.date > cutoff }
    }

    private static let sentRecordsKey = "fixa.sentRecords"
    /// The longest window `SendGuard` looks back over.
    private static let sentRecordLifetime = max(SendGuard.duplicateWindow, SendGuard.limits.map { $0.window }.max() ?? 0)

    /// A send whose final step went out: a receipt, or no answer (may have been sent).
    private func recordSend(_ draft: ReportDraft, date: Date, caseNumber: String?) {
        var record = SentRecord(draft, date: date)
        record.caseNumber = caseNumber
        guardRecords = sentRecords + [record]
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
                var record = SentRecord(date: item.date, tileID: item.tileID, coordinate: coordinate, locationText: item.locationText)
                record.caseNumber = item.caseNumber
                return record
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
        let message: String
        if sendsPaused != nil {
            message = String(localized: "Your report is saved on this phone. Fixa isn't sending on its own right now. Open Sent reports to use the kommun's website instead.", bundle: L10n.bundle, locale: L10n.locale)
        } else if isOnline {
            message = String(localized: "Your report is saved on this phone. Fixa tries again in a little while, also in the background.", bundle: L10n.bundle, locale: L10n.locale)
        } else {
            message = String(localized: "Your report is saved on this phone. Fixa sends it when you're back online, also in the background.", bundle: L10n.bundle, locale: L10n.locale)
        }
        return OutboxNotice(title: String(localized: "Waiting to send", bundle: L10n.bundle, locale: L10n.locale), message: message)
    }

    // MARK: Kommun's website

    /// The report as plain Swedish text to paste into the kommun's own web form.
    func webFallbackText(for draft: ReportDraft) -> String {
        guard let spec else { return "" }
        return WebFallback.text(draft, spec: spec)
    }

    /// `webFallbackText(for:)` for a report in the outbox; nil once it is gone.
    func webFallbackText(id: UUID) -> String? {
        guard let draft = outbox.item(id: id)?.draft else { return nil }
        return webFallbackText(for: draft)
    }

    /// Copies `text` (this phone only, for an hour) and opens the kommun's own web form (in-app Safari),
    /// where the user pastes it and attaches the photo themselves.
    func openWebForm(_ text: String) {
        UIPasteboard.general.setItems(
            [[UTType.utf8PlainText.identifier: text]],
            options: [.localOnly: true, .expirationDate: Date.now.addingTimeInterval(60 * 60)]
        )
        guard let spec else { return }
        KommunWeb.open(spec.webFormURL, spec: spec)
    }

    /// Whether a waiting or unconfirmed report asked for a reply by e-mail (and so gets a confirmation).
    func wantsReply(_ id: UUID) -> Bool {
        outbox.item(id: id)?.draft.wantsFeedback ?? false
    }

    /// The e-service asked Fixa to wait until then; not even "Try again" sends this report sooner.
    func retryBlockedUntil(_ id: UUID) -> Date? {
        guard let until = outbox.item(id: id)?.serverRetryAfter, until > .now else { return nil }
        return until
    }

    /// The user's explicit "Try again" on a report Fixa stopped sending, or a confirmed
    /// "Send again anyway" on one that may have arrived. Skips Fixa's own back-off, never the
    /// e-service's `Retry-After` (`retryBlockedUntil`). Already confirmed, so no repeat warning,
    /// but the hourly/daily cap still applies.
    func sendNow(_ id: UUID) async {
        guard var item = outbox.item(id: id), !sendingIDs.contains(id), item.finalSendAt == nil else { return }
        if options.demo {
            // No network in demo: pretend it went through.
            outbox.remove([id])
            markSent(id, SentReport(caseNumber: DemoData.receipt.caseNumber, date: .now, isDryRun: false, kommunMessage: DemoData.receipt.kommunMessage))
            return
        }
        guard retryBlockedUntil(id) == nil else { return }
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
                await self?.flushOutbox()
            }
        }
        scheduleRetry()
    }

    /// The first path update after launch tries the reports whose back-off has passed. A
    /// connection coming back waits a random 0–60 s first, then does the same.
    private func connectivityChanged(online: Bool) {
        isOnline = online
        let previous = lastPathOnline
        lastPathOnline = online
        guard previous != online else { return }
        reconnectTask?.cancel()
        guard online else { return }
        guard previous == false else {
            Task { await flushOutbox() }
            return
        }
        let wait = Double.random(in: 0...Self.reconnectSpread)
        reconnectTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(wait))
            guard !Task.isCancelled else { return }
            await self?.flushOutbox()
        }
    }

    /// Single flight: if a flush is already running, this asks it for one more pass and waits for
    /// it, so foreground, connectivity, timer and background task firing together run one loop.
    /// Returns when the outbox has had its try.
    private func flushOutbox() async {
        guard persists else { return }
        if let running = flushTask {
            flushAgain = true
            await running.value
            return
        }
        // Main-actor task: set before it can start, cleared by itself before it ends.
        let task = Task { [self] in
            repeat {
                flushAgain = false
                await flushPass()
            } while flushAgain && !stopsOutboxAfterCurrentSend
            flushTask = nil
            scheduleRetry()
        }
        flushTask = task
        await task.value
    }

    /// Reports Fixa may try on its own now: not held, not mid-send, tries left, back-off and
    /// `Retry-After` passed. None while sends are paused.
    private func isDue(_ item: PendingReport, at now: Date) -> Bool {
        sendsPaused == nil && !item.held && item.finalSendAt == nil
            && item.attempts < Self.maxAutomaticAttempts && item.nextAttemptAt <= now
            && (item.serverRetryAfter ?? .distantPast) <= now
    }

    /// One try for each report whose back-off has passed. Never touches held reports (may have
    /// been sent, not sent).
    private func flushPass() async {
        guard lastPathOnline == true else { return }
        let now = Date.now
        let due = outbox.items.filter { isDue($0, at: now) }.map(\.id)
        for id in due {
            guard lastPathOnline == true, !stopsOutboxAfterCurrentSend else { break }
            await attempt(id, automatic: true)
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
        await flushOutbox()
    }

    /// Sends one outbox report and waits for the e-service's final answer. Single flight per id:
    /// the check and the insert into `sendingIDs` run on the main actor with no await between.
    private func attempt(_ id: UUID, automatic: Bool) async {
        guard persists, let spec, var item = outbox.item(id: id), !sendingIDs.contains(id), item.finalSendAt == nil else { return }
        // Re-read: another trigger may have tried it since this pass picked it.
        if automatic, !isDue(item, at: .now) { return }
        if let until = item.serverRetryAfter, until > .now { return }
        // Rate limit counts retries too; waiting for it is not a failed try.
        if case .tooMany(let retryAfter) = sendGuardDecision(for: item.draft, checksDuplicate: false) {
            item.nextAttemptAt = max(item.nextAttemptAt, retryAfter)
            outbox.put(item)
            return
        }
        sendingIDs.insert(id)
        defer { sendingIDs.remove(id) }
        let service = SubmissionService()
        let report = item.draft
        let mark: @Sendable () async -> Void = { [weak self] in await self?.markFinalSend(id, draft: report) }
        var result = await service.submit(report, spec: spec, dryRun: false, beforeFinalSend: mark)
        // Form drift stops before the final step: once more with a newer signed adapter, if any.
        if result == nil, case .formChanged? = service.error,
           await refreshAdapterAfterFormChange(), let fresh = self.spec {
            service.reset()
            result = await service.submit(report, spec: fresh, dryRun: false, beforeFinalSend: mark)
        }
        if let result {
            if !automatic {
                setSendsPaused(nil)
            }
            recordSend(report, date: result.date, caseNumber: result.caseNumber)
            outbox.remove([id])
            markSent(id, result)
            return
        }
        // Cancelled before the final step: nothing is known, so nothing changes.
        guard let error = service.error ?? interruptedAfterFinalSend(id) else { return }
        pauseIfRefused(error)
        let now = Date.now
        // `item` predates the final-step mark, so writing it back clears the mark.
        item.finalSendAt = nil
        item.attempts += 1
        item.serverRetryAfter = Self.serverRetryAfter(error, now: now)
        let status: HistoryItem.Status
        if error.isRetrySafe, item.attempts < Self.maxAutomaticAttempts {
            item.nextAttemptAt = Self.nextAttemptDate(afterAttempts: item.attempts, error: error, now: now)
            status = .waiting
        } else if case .uncertain = error {
            // Never sent again on its own; counts as a send for the guard.
            recordSend(report, date: now, caseNumber: nil)
            item.held = true
            status = .maybeSent
        } else {
            // Tries ran out, or retrying can't help (form changed, refused, rejected): the user decides.
            item.held = true
            status = .notSent
        }
        outbox.put(item)
        history.update(id: id) { $0.status = status }
        if sent?.historyID == id {
            sent?.outcome = status == .maybeSent ? .maybeSent : .waiting
        }
    }

    private func markSent(_ id: UUID, _ result: SentReport) {
        history.update(id: id) {
            $0.status = .sent
            $0.caseNumber = result.caseNumber
            $0.date = result.date
            $0.record(result)
        }
        if sent?.historyID == id {
            var receipt = result
            receipt.outcome = .sent
            receipt.historyID = id
            sent = receipt
        }
    }

    // MARK: Final-step mark

    /// Runs right before a report's final step goes out (the user's Send and outbox sends alike):
    /// writes to disk, before returning, that it is going out. If the app dies before the outcome
    /// is recorded, the next launch finds the mark (`settleInterruptedSends`).
    private func markFinalSend(_ id: UUID, draft: ReportDraft) {
        guard persists else { return }
        var item = outbox.item(id: id)
            ?? PendingReport(id: id, draft: draft, createdAt: .now, attempts: 0, nextAttemptAt: .now, held: false)
        item.finalSendAt = .now
        outbox.put(item)
    }

    /// At launch: every report whose final step went out with no outcome recorded may have been
    /// sent. It is held (never sent again on its own), counts for `SendGuard`, shows in Sent
    /// reports as "may have been sent", and its saved draft does not reopen.
    private func settleInterruptedSends() {
        for var item in outbox.items {
            guard let markedAt = item.finalSendAt else { continue }
            item.finalSendAt = nil
            item.held = true
            item.attempts = max(item.attempts, 1)
            recordSend(item.draft, date: markedAt, caseNumber: nil)
            outbox.put(item)
            if history.item(id: item.id) == nil {
                history.add(historyItem(id: item.id, from: item.draft, date: markedAt, caseNumber: nil, status: .maybeSent))
            } else {
                history.update(id: item.id) { $0.status = .maybeSent }
            }
            if let saved = DraftStore.loadDraft(), saved.createdAt == item.draft.createdAt, saved.description == item.draft.description {
                DraftStore.clear()
            }
        }
    }

    // MARK: Paused sends

    private func setSendsPaused(_ pause: SendsPause?) {
        guard pause != sendsPaused else { return }
        sendsPaused = pause
        if persists {
            if let pause {
                UserDefaults.standard.set(pause.rawValue, forKey: Self.sendsPausedKey)
            } else {
                UserDefaults.standard.removeObject(forKey: Self.sendsPausedKey)
            }
        }
        scheduleRetry()
    }

    /// The e-service refused Fixa or asked for a login: nothing more goes out on its own.
    private func pauseIfRefused(_ error: SubmissionError) {
        switch error {
        case .blocked: setSendsPaused(.blocked)
        case .loginRequired: setSendsPaused(.loginRequired)
        default: break
        }
    }

    /// The status file says down: pause. Back to ok: lifts a pause it caused, and any pause when
    /// it was down before (the e-service is back for everyone).
    private func syncSendsPauseWithStatus(previous: AdapterStatus.State? = nil) {
        guard persists else { return }
        let state = adapters.status.state
        if state == .down {
            if sendsPaused == nil { setSendsPaused(.serviceDown) }
        } else if sendsPaused == .serviceDown || previous == .down {
            setSendsPaused(nil)
        }
    }

    /// `AdapterStore.refreshAfterFormChange` plus the status it may bring along.
    private func refreshAdapterAfterFormChange() async -> Bool {
        let previous = adapters.status.state
        let changed = await adapters.refreshAfterFormChange()
        syncSendsPauseWithStatus(previous: previous)
        return changed
    }

    /// The earliest moment an outbox report is due on its own; nil while paused or none waits.
    private var nextAutomaticAttempt: Date? {
        guard sendsPaused == nil else { return nil }
        return outbox.items
            .filter { !$0.held && $0.finalSendAt == nil && $0.attempts < Self.maxAutomaticAttempts }
            .map { max($0.nextAttemptAt, $0.serverRetryAfter ?? .distantPast) }
            .min()
    }

    /// Wakes for the earliest back-off while the app runs, and asks iOS for a background task at
    /// the same time for when it doesn't. The flush runs in its own task so rescheduling never
    /// cancels a send already under way. Called whenever a report is queued or a back-off is set.
    private func scheduleRetry() {
        retryTask?.cancel()
        guard persists else { return }
        let next = nextAutomaticAttempt
        BackgroundOutbox.schedule(earliest: next)
        guard let next else { return }
        retryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(max(1, next.timeIntervalSinceNow)))
            guard !Task.isCancelled else { return }
            Task { @MainActor [weak self] in await self?.flushOutbox() }
        }
    }

    /// When the app leaves the screen: makes sure iOS knows about waiting reports.
    func scheduleBackgroundSend() {
        guard persists else { return }
        BackgroundOutbox.schedule(earliest: nextAutomaticAttempt)
    }

    // MARK: Launch hooks

    private func seedDemo() {
        profileStorage = DemoData.profile
        var demo = DemoData.draft(adapterID: spec?.id ?? Self.adapterID)
        if let tile = options.tile, spec?.tile(id: tile) != nil { demo.tileID = tile }
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
        history.add(historyItem(id: id, from: draft, date: now, caseNumber: nil, status: status))
        sent = SentReport(caseNumber: nil, date: now, isDryRun: false, outcome: status == .waiting ? .waiting : .maybeSent, historyID: id)
        isOnline = status != .waiting
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
