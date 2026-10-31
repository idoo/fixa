import FixaKit
import MapKit
import NaturalLanguage
import SwiftUI
import Translation
import UIKit

/// Exactly what will be sent, then Send (pinned at the bottom) with progress and fallbacks.
struct ReviewScreen: View {
    let spec: AdapterSpec
    @Environment(AppModel.self) private var model
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.fxReduceMotion) private var reduceMotion
    /// Set to start "Tell Fixa about it" (an e-mail to the developer the user sees before sending).
    @State private var developerReport: DeveloperReport?
    /// Drives the on-device Swedish translation of the description and typed place; nil until one is needed.
    @State private var translationConfig: TranslationSession.Configuration?
    @State private var translationState: TranslationState = .idle
    /// VoiceOver focus moves here when sending fails: the status slot, or the form-changed card.
    @AccessibilityFocusState private var failureFocused: Bool

    private static let driftCardID = "formChanged"
    /// Send waits at most this long for the Swedish translation, then the text goes as written.
    private static let translationCap: Duration = .seconds(15)

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: Fx.Space.l) {
                    if let drift = formDrift {
                        formChangedCard(drift)
                            .id(Self.driftCardID)
                    }
                    if let other = model.outsideMunicipalityName {
                        FxBanner(
                            kind: .warning,
                            title: String(localized: "Outside Värmdö", bundle: L10n.bundle, locale: L10n.locale),
                            message: String(localized: "This place is in \(other). Fixa only sends reports to Värmdö kommun.", bundle: L10n.bundle, locale: L10n.locale)
                        )
                    }
                    if let pause = model.sendsPaused, model.submission.error == nil {
                        FxBanner(
                            kind: .warning,
                            title: String(localized: "Fixa can't send right now", bundle: L10n.bundle, locale: L10n.locale),
                            message: pause.message
                        )
                        WebFormFallback(text: model.webFallbackText(for: model.draft), spec: spec, tileID: model.draft.tileID)
                    }
                    Text("This is what \(spec.municipality.name) receives")
                        .font(Fx.Font.callout)
                        .foregroundStyle(Fx.Color.ink2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                    summaryCard
                    if model.options.dryRun {
                        FxBanner(
                            kind: .info,
                            title: String(localized: "Test mode", bundle: L10n.bundle, locale: L10n.locale),
                            message: String(localized: "Fixa stops before the last step. Nothing is submitted.", bundle: L10n.bundle, locale: L10n.locale)
                        )
                    }
                    // The disclaimer always comes from the adapter shipped in the app, never from a download.
                    if let disclaimer = AdapterCatalog.shipped(id: spec.id)?.disclaimer {
                        FxBanner(kind: .info, title: String(localized: "Good to know", bundle: L10n.bundle, locale: L10n.locale), message: disclaimer.resolve(L10n.locale))
                    }
                    Text("Reports become public records. Leave out faces, plates and names.")
                        .font(Fx.Font.footnote)
                        .foregroundStyle(Fx.Color.ink2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, Fx.Space.l)
                .padding(.top, Fx.Space.s)
                .padding(.bottom, Fx.Space.l)
            }
            .onChange(of: model.submission.phase) { _, phase in
                announce(phase, scrollingWith: proxy)
            }
        }
        .fxScreenBackground()
        .fxBottomBar { sendBar }
        .navigationTitle(Text("Review"))
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(model.submission.isSending)
        .developerReport($developerReport)
        .onAppear(perform: prepareTranslation)
        .translationTask(translationConfig) { session in
            await translate(with: session)
        }
        .task(id: translationState) {
            guard translationState == .translating,
                  (try? await Task.sleep(for: Self.translationCap)) != nil,
                  translationState == .translating else { return }
            translationState = .unavailable
        }
    }

    // MARK: Summary

    private var summaryCard: some View {
        FxCard {
            editableRow(String(localized: "Category", bundle: L10n.bundle, locale: L10n.locale)) {
                value(problemTitle)
                if let category = municipalityCategory {
                    Text(category)
                        .font(Fx.Font.callout)
                        .foregroundStyle(Fx.Color.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            divider
            editableRow(String(localized: "Place", bundle: L10n.bundle, locale: L10n.locale)) {
                value(placeText)
                if let translated = model.draft.translation?.locationText {
                    Text("Sent with a Swedish translation: \(translated)")
                        .font(Fx.Font.footnote)
                        .foregroundStyle(Fx.Color.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let coordinate = model.draft.coordinate {
                    Map(initialPosition: .region(MKCoordinateRegion(
                        center: coordinate.clLocation,
                        latitudinalMeters: 400,
                        longitudinalMeters: 400
                    )), interactionModes: []) {
                        Marker(placeText, coordinate: coordinate.clLocation)
                            .tint(Fx.Color.sea)
                    }
                    .frame(height: 160)
                    .clipShape(RoundedRectangle(cornerRadius: Fx.Radius.s, style: .continuous))
                    .fxOutline(RoundedRectangle(cornerRadius: Fx.Radius.s, style: .continuous), fill: .clear)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                    .padding(.top, Fx.Space.xs)
                }
            }
            divider
            editableRow(isSwedishUI
                ? String(localized: "Description, as sent", bundle: L10n.bundle, locale: L10n.locale)
                : String(localized: "Description", bundle: L10n.bundle, locale: L10n.locale)) {
                if isSwedishUI {
                    value(ReportComposer.description(for: model.draft, spec: spec))
                } else {
                    // The resident's own words first; below, exactly what the kommun receives.
                    value(model.draft.description.trimmingCharacters(in: .whitespacesAndNewlines))
                    VStack(alignment: .leading, spacing: Fx.Space.xs) {
                        Text("As sent, in Swedish")
                            .font(Fx.Font.section)
                            .foregroundStyle(Fx.Color.ink2)
                        Text(ReportComposer.description(for: model.draft, spec: spec))
                            .font(Fx.Font.callout)
                            .foregroundStyle(Fx.Color.ink)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                            .environment(\.locale, Locale(identifier: "sv_SE"))
                    }
                    .padding(.top, Fx.Space.xs)
                }
                translationNote
                    .font(Fx.Font.footnote)
                    .foregroundStyle(Fx.Color.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            divider
            editableRow(String(localized: "Photo", bundle: L10n.bundle, locale: L10n.locale)) {
                if let data = model.draft.photoJPEG, let image = UIImage(data: data) {
                    photo(image)
                } else {
                    Text("No photo")
                        .font(Fx.Font.body)
                        .foregroundStyle(Fx.Color.ink2)
                }
            }
            divider
            editableRow(String(localized: "Reply", bundle: L10n.bundle, locale: L10n.locale), extraInputLabel: String(localized: "Change reply details", bundle: L10n.bundle, locale: L10n.locale)) {
                value(replySummary)
            }
        }
    }

    /// The tile people chose ("Streetlight out"); the category when there is no tile.
    private var problemTitle: String {
        spec.tile(id: model.draft.tileID)?.title.resolve(L10n.locale)
            ?? spec.category(for: model.draft)?.title.resolve(L10n.locale)
            ?? "–"
    }

    /// The municipality's own category, shown under the tile title when it says something different.
    private var municipalityCategory: String? {
        guard spec.tile(id: model.draft.tileID) != nil,
              let category = spec.category(for: model.draft)?.title.resolve(L10n.locale),
              category != problemTitle else { return nil }
        return category
    }

    /// Address or place text only; never coordinates.
    private var placeText: String {
        let text = model.draft.locationText.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? String(localized: "Pin on the map", bundle: L10n.bundle, locale: L10n.locale) : text
    }

    /// A Swedish UI shows the text exactly as sent; any other language puts the resident's own words first.
    private var isSwedishUI: Bool { L10n.effectiveLanguage == .sv }

    // MARK: Translation

    private enum TranslationState: Equatable {
        case idle, translating, unavailable
    }

    /// What happens to the resident's text, in plain words. The translation itself is in the
    /// description above, under "Översatt från …:", exactly as the municipality receives it.
    private var translationNote: Text {
        if let translated = model.draft.translation?.text, !translated.isEmpty {
            return Text("Sent as written, with a Swedish translation added.")
        }
        switch translationState {
        case .translating:
            return Text("Translating your text into Swedish…")
        case .unavailable:
            return Text("Sent as written; this iPhone couldn't translate it.")
        case .idle:
            return Text("Sent as written.")
        }
    }

    /// The language of `text` when it is clear, else the app's. Nil when it is Swedish.
    /// `swedishLetters`: an unclear text with å, ä or ö counts as Swedish (short place names).
    private func nonSwedishLanguage(of text: String, swedishLetters: Bool = false) -> Locale.Language? {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        var source = L10n.locale.language
        if let detected = recognizer.dominantLanguage,
           (recognizer.languageHypotheses(withMaximum: 1)[detected] ?? 0) >= 0.6 {
            source = Locale.Language(identifier: detected.rawValue)
        } else if swedishLetters, text.contains(where: { "åäöÅÄÖ".contains($0) }) {
            return nil
        }
        return source.languageCode?.identifier == "sv" ? nil : source
    }

    /// The resident's own description, when it needs a translation.
    private var descriptionToTranslate: (text: String, source: Locale.Language)? {
        let text = model.draft.description.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let source = nonSwedishLanguage(of: text) else { return nil }
        return (text, source)
    }

    /// The place, only when the resident typed it (an automatic address is already Swedish).
    private var placeToTranslate: (text: String, source: Locale.Language)? {
        guard model.placeTextIsTyped else { return nil }
        let text = model.draft.locationText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let source = nonSwedishLanguage(of: text, swedishLetters: true) else { return nil }
        return (text, source)
    }

    /// What one translation session translates: the description's language decides; the place
    /// goes along when it is in the same language. Nil when nothing needs translating.
    private var translationPlan: (source: Locale.Language, description: String?, place: String?)? {
        let description = descriptionToTranslate
        let place = placeToTranslate
        guard let source = description?.source ?? place?.source else { return nil }
        return (source, description?.text, place?.source == source ? place?.text : nil)
    }

    /// Starts an on-device translation into Swedish when the text needs one and has none yet.
    /// The Report screen clears `draft.translation` whenever the description changes; a typed
    /// place is translated again each time, since it may have changed since.
    private func prepareTranslation() {
        guard let plan = translationPlan else {
            model.draft.translation = nil
            translationState = .idle
            return
        }
        if plan.place == nil, let existing = model.draft.translation,
           existing.sourceLanguage == plan.source.languageCode?.identifier, existing.locationText == nil {
            return
        }
        model.draft.translation = nil
        translationState = .translating
        if translationConfig?.source == plan.source {
            translationConfig?.invalidate()
        } else {
            translationConfig = TranslationSession.Configuration(source: plan.source, target: Locale.Language(identifier: "sv"))
        }
    }

    /// Translates with Apple's on-device Translation. If the languages aren't available or the
    /// download is declined, the text goes as written and the note says so.
    private func translate(with session: TranslationSession) async {
        guard let plan = translationPlan, let code = plan.source.languageCode?.identifier else { return }
        var requests: [TranslationSession.Request] = []
        if let text = plan.description {
            requests.append(TranslationSession.Request(sourceText: text, clientIdentifier: "description"))
        }
        if let text = plan.place {
            requests.append(TranslationSession.Request(sourceText: text, clientIdentifier: "place"))
        }
        do {
            // The session belongs to this `.translationTask` call and is used only here, as in Apple's
            // samples; region isolation can't see that, so opt out for this one call.
            nonisolated(unsafe) let session = session
            let responses = try await session.translations(from: requests)
            // The resident may have gone back and changed the text, or already sent it.
            guard let current = translationPlan, current.description == plan.description, current.place == plan.place,
                  !model.submission.isSending else { return }
            func swedish(_ id: String, original: String?) -> String? {
                guard let original,
                      let text = responses.first(where: { $0.clientIdentifier == id })?.targetText.trimmingCharacters(in: .whitespacesAndNewlines),
                      !text.isEmpty, text != original else { return nil }
                return text
            }
            let description = swedish("description", original: plan.description)
            let place = swedish("place", original: plan.place)
            if description != nil || place != nil {
                var translation = MachineTranslation(sourceLanguage: code, text: description ?? "")
                translation.locationText = place
                model.draft.translation = translation
            }
            translationState = .idle
        } catch {
            translationState = .unavailable
        }
    }

    /// E-mail and phone are isolated left-to-right so "+46…" and "@" keep their order in Arabic.
    private var replySummary: String {
        guard model.draft.wantsFeedback else { return String(localized: "No reply requested", bundle: L10n.bundle, locale: L10n.locale) }
        let c = model.draft.contact
        let name = [c.firstName, c.lastName].filter { !$0.isEmpty }.joined(separator: " ")
        let email = c.email.isEmpty ? "" : c.email.ltrIsolated
        let phone = c.phone.isEmpty ? "" : c.phone.ltrIsolated
        return [name, email, phone].filter { !$0.isEmpty }.joined(separator: "\n")
    }

    /// Fills the card width at the photo's own aspect, capped at square so tall shots don't take over.
    private func photo(_ image: UIImage) -> some View {
        let ratio = image.size.height > 0 ? max(image.size.width / image.size.height, 1) : 1
        return Color.clear
            .frame(maxWidth: .infinity)
            .aspectRatio(ratio, contentMode: .fit)
            .overlay {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            }
            .clipShape(RoundedRectangle(cornerRadius: Fx.Radius.s, style: .continuous))
            .fxOutline(RoundedRectangle(cornerRadius: Fx.Radius.s, style: .continuous), fill: .clear)
            .padding(.top, Fx.Space.xs)
            .accessibilityElement()
            .accessibilityLabel(Text("Attached photo"))
    }

    private var divider: some View {
        FxDivider()
    }

    private func value(_ text: String) -> some View {
        Text(text)
            .font(Fx.Font.body)
            .foregroundStyle(Fx.Color.ink)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// A summary section; the whole row goes back to the report to change it.
    /// "Edit" is hidden from VoiceOver but stays a Voice Control name ("Tap Edit Place").
    private func editableRow<Content: View>(
        _ title: String,
        extraInputLabel: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        let header = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Fx.Space.xs))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: Fx.Space.s))
        var inputLabels = [Text("Edit \(title)"), Text(title)]
        if let extraInputLabel { inputLabels.append(Text(extraInputLabel)) }
        return Button(action: editReport) {
            VStack(alignment: .leading, spacing: Fx.Space.xs) {
                header {
                    Text(title)
                        .font(Fx.Font.subheadline)
                        .foregroundStyle(Fx.Color.ink)
                    if !dynamicTypeSize.isAccessibilitySize {
                        Spacer(minLength: Fx.Space.s)
                    }
                    Text("Edit")
                        .font(Fx.Font.footnote.weight(.bold))
                        .foregroundStyle(Fx.Color.sea)
                        .accessibilityHidden(true)
                }
                content()
            }
            .frame(maxWidth: .infinity, minHeight: Fx.minTarget, alignment: .leading)
            .contentShape(.rect)
        }
        .buttonStyle(FxPressStyle())
        .disabled(model.submission.isSending)
        .accessibilityElement(children: .combine)
        .accessibilityHint(Text("Opens the report to change it"))
        .accessibilityInputLabels(inputLabels)
    }

    private func editReport() {
        guard model.path.last == .review else { return }
        model.path.removeLast()
    }

    // MARK: Form changed

    private var formDrift: FormDrift? {
        if case .formChanged(let drift) = model.submission.error { return drift }
        return nil
    }

    /// Kind, blame-free: the municipality updated its e-service and Fixa hasn't caught up yet.
    /// The draft is kept; the bottom bar offers the kommun's website.
    private func formChangedCard(_ drift: FormDrift) -> some View {
        FxCard {
            VStack(alignment: .leading, spacing: Fx.Space.m) {
                VStack(alignment: .leading, spacing: Fx.Space.s) {
                    FxBadge(systemImage: "wrench.and.screwdriver", fill: Fx.Color.categoryTint(nil), side: 44)
                    Text("The municipality seems to have changed its form")
                        .font(Fx.Font.headline)
                        .foregroundStyle(Fx.Color.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                    Text("Fixa is an independent app, so sometimes we notice a little later. Your report is saved on this phone. We'll fix Fixa as soon as we can.")
                        .font(Fx.Font.body)
                        .foregroundStyle(Fx.Color.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
                .accessibilityFocused($failureFocused)
                Button {
                    developerReport = DeveloperReport(spec: spec, error: .formChanged(drift))
                } label: {
                    Text("Tell Fixa about it")
                        .font(Fx.Font.callout)
                        .foregroundStyle(Fx.Color.sea)
                        .underline()
                        .frame(maxWidth: .infinity, minHeight: Fx.minTarget, alignment: .leading)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityHint(Text("Opens an e-mail to the developer with technical details only. You see it before it's sent."))
            }
        }
    }

    // MARK: Send

    /// Pinned at the bottom. Progress and errors take the status slot above the button,
    /// which keeps one fixed height so steps and errors swap without the bar jumping.
    @ViewBuilder
    private var sendBar: some View {
        let submission = model.submission
        if formDrift != nil {
            // Trying again won't help until the adapter is updated: the kommun's website is the way through.
            WebFormFallback(text: model.webFallbackText(for: model.draft), spec: spec, tileID: model.draft.tileID)
        } else if let error = submission.error {
            statusSlot
                .transition(.opacity)
            if !error.isUncertain {
                FxPrimaryButton(title: String(localized: "Try again", bundle: L10n.bundle, locale: L10n.locale), systemImage: "arrow.clockwise", action: send)
            }
            if error.offersWebForm {
                WebFormFallback(text: model.webFallbackText(for: model.draft), spec: spec, tileID: model.draft.tileID)
            }
        } else {
            if submission.isSending {
                statusSlot
                    .transition(.opacity)
            }
            // Waits for the Swedish translation (at most `translationCap`) so it goes with the report.
            let translating = translationState == .translating && !submission.isSending
            FxPrimaryButton(
                title: translating
                    ? String(localized: "Translating…", bundle: L10n.bundle, locale: L10n.locale)
                    : String(localized: "Send to \(spec.municipality.name)", bundle: L10n.bundle, locale: L10n.locale),
                systemImage: "paperplane",
                isLoading: submission.isSending || translating,
                action: send
            )
            .accessibilityIdentifier("review.send")
        }
    }

    private var statusSlot: some View {
        let submission = model.submission
        return ZStack(alignment: .topLeading) {
            if case .sending(let stage) = submission.phase {
                VStack(alignment: .leading, spacing: Fx.Space.s) {
                    FxProgressSteps(current: stage.stepIndex, total: SubmissionStage.stepCount)
                    Text(stage.label)
                        .font(Fx.Font.callout)
                        .foregroundStyle(Fx.Color.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
            } else if let error = submission.error {
                HStack(alignment: .firstTextBaseline, spacing: Fx.Space.s) {
                    Image(systemName: "wifi.exclamationmark")
                        .foregroundStyle(Fx.Color.ink2)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: Fx.Space.xs) {
                        Text("Not sent")
                            .font(Fx.Font.callout.weight(.semibold))
                            .foregroundStyle(Fx.Color.ink)
                        if case .serverValidation(let messages) = error, !messages.isEmpty {
                            // The e-service's own words, in the app's language; the Swedish one tap away.
                            Text("The e-service says:")
                                .font(Fx.Font.callout)
                                .foregroundStyle(Fx.Color.ink2)
                            KommunTextView(swedish: messages.joined(separator: "\n"), spec: spec, quoted: false)
                        } else {
                            Text(error.userMessage(spec: spec))
                                .font(Fx.Font.callout)
                                .foregroundStyle(Fx.Color.ink2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Text("Your report is saved on this phone.")
                            .font(Fx.Font.footnote)
                            .foregroundStyle(Fx.Color.ink2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityFocused($failureFocused)
            }
        }
        .frame(maxWidth: .infinity, minHeight: Fx.minTarget, alignment: .topLeading)
        .animation(reduceMotion ? nil : Fx.Motion.select, value: submission.phase)
    }

    /// Reads each step aloud while sending; on failure moves VoiceOver to what went wrong.
    private func announce(_ phase: SubmissionService.Phase, scrollingWith proxy: ScrollViewProxy) {
        switch phase {
        case .idle:
            break
        case .sending(let stage):
            AccessibilityNotification.Announcement(stage.label).post()
        case .failed(let error):
            if case .formChanged = error {
                withAnimation(reduceMotion ? nil : Fx.Motion.select) {
                    proxy.scrollTo(Self.driftCardID, anchor: .top)
                }
            }
            AccessibilityNotification.Announcement(String(localized: "Not sent. \(error.userMessage(spec: spec))", bundle: L10n.bundle, locale: L10n.locale)).post()
            failureFocused = true
        }
    }

    private func send() {
        Task { await model.send() }
    }
}
