import FixaKit
import MapKit
import SwiftUI
import UIKit

/// Exactly what will be sent, then Send (pinned at the bottom) with progress and fallbacks.
struct ReviewScreen: View {
    let spec: AdapterSpec
    @Environment(AppModel.self) private var model
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.fxReduceMotion) private var reduceMotion
    @State private var isMailPresented = false
    @State private var isSharePresented = false
    /// VoiceOver focus moves here when sending fails: the status slot, or the form-changed card.
    @AccessibilityFocusState private var failureFocused: Bool

    private static let driftCardID = "formChanged"

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: Fx.Space.l) {
                    if let drift = formDrift {
                        formChangedCard(drift)
                            .id(Self.driftCardID)
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
                    FxBanner(kind: .info, title: String(localized: "Good to know", bundle: L10n.bundle, locale: L10n.locale), message: spec.disclaimer.resolve(L10n.locale))
                    if model.submission.error != nil, formDrift == nil, !MailComposer.canSendMail {
                        mailUnavailableFallback
                    }
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
        .sheet(isPresented: $isMailPresented) {
            MailComposer(
                recipients: [spec.fallbackEmail].compactMap { $0 },
                subject: MailFallback.subject(model.draft, spec: spec),
                body: MailFallback.body(model.draft, spec: spec),
                attachment: model.draft.photoJPEG.map {
                    MailComposer.Attachment(data: $0, mimeType: "image/jpeg", fileName: "fixa.jpg")
                },
                onFinish: { _ in isMailPresented = false }
            )
            .ignoresSafeArea()
        }
        .sheet(isPresented: $isSharePresented) {
            ShareSheet(items: shareItems)
                .presentationDetents([.medium, .large])
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
                if let coordinate = model.draft.coordinate {
                    Map(initialPosition: .region(MKCoordinateRegion(
                        center: coordinate.clLocation,
                        latitudinalMeters: 400,
                        longitudinalMeters: 400
                    )), interactionModes: []) {
                        Marker(placeText, coordinate: coordinate.clLocation)
                            .tint(Fx.Color.sea)
                    }
                    .frame(height: 120)
                    .clipShape(RoundedRectangle(cornerRadius: Fx.Radius.s, style: .continuous))
                    .fxOutline(RoundedRectangle(cornerRadius: Fx.Radius.s, style: .continuous), fill: .clear)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                    .padding(.top, Fx.Space.xs)
                }
            }
            divider
            editableRow(String(localized: "Description, as sent", bundle: L10n.bundle, locale: L10n.locale)) {
                value(ReportComposer.description(for: model.draft, spec: spec))
                Text("Fixa adds this Swedish summary so the municipality understands.")
                    .font(Fx.Font.footnote)
                    .foregroundStyle(Fx.Color.ink2)
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
                        .foregroundStyle(Fx.Color.ink2)
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
    /// The draft is kept; the bottom bar offers e-mail, the card the other ways to send it.
    private func formChangedCard(_ drift: FormDrift) -> some View {
        FxCard {
            VStack(alignment: .leading, spacing: Fx.Space.m) {
                VStack(alignment: .leading, spacing: Fx.Space.s) {
                    FxBadge(systemImage: "wrench.and.screwdriver", fill: Fx.Color.Pastel.sun, side: 44)
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
                if let url = spec.eServiceURL {
                    FxSecondaryButton(title: String(localized: "Open the municipality's form", bundle: L10n.bundle, locale: L10n.locale), systemImage: "safari") {
                        UIApplication.shared.open(url)
                    }
                }
                FxCopyButton(title: String(localized: "Copy report text", bundle: L10n.bundle, locale: L10n.locale), value: mailText)
                if let url = drift.issueURL(spec: spec) {
                    Link(destination: url) {
                        Text("Tell Fixa about it")
                            .font(Fx.Font.callout)
                            .foregroundStyle(Fx.Color.sea)
                            .underline()
                            .frame(maxWidth: .infinity, minHeight: Fx.minTarget, alignment: .leading)
                            .contentShape(.rect)
                    }
                    .accessibilityHint(Text("Opens a GitHub page. Only the app version and the form's page are filled in."))
                }
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
            // Trying again won't help until the adapter is updated: e-mail is the way through.
            FxPrimaryButton(title: String(localized: "Send by e-mail instead", bundle: L10n.bundle, locale: L10n.locale), systemImage: "envelope", action: sendByMail)
        } else if submission.error != nil {
            statusSlot
                .transition(.opacity)
            FxPrimaryButton(title: String(localized: "Try again", bundle: L10n.bundle, locale: L10n.locale), systemImage: "arrow.clockwise", action: send)
            FxSecondaryButton(title: String(localized: "Send by e-mail instead", bundle: L10n.bundle, locale: L10n.locale), systemImage: "envelope", action: sendByMail)
        } else {
            if submission.isSending {
                statusSlot
                    .transition(.opacity)
            }
            FxPrimaryButton(
                title: String(localized: "Send to \(spec.municipality.name)", bundle: L10n.bundle, locale: L10n.locale),
                systemImage: "paperplane",
                isLoading: submission.isSending,
                action: send
            )
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
                        Text(error.userMessage)
                            .font(Fx.Font.callout)
                            .foregroundStyle(Fx.Color.ink2)
                            .fixedSize(horizontal: false, vertical: true)
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
            AccessibilityNotification.Announcement(String(localized: "Not sent. \(error.userMessage)", bundle: L10n.bundle, locale: L10n.locale)).post()
            failureFocused = true
        }
    }

    /// Mail isn't set up: the share sheet is the e-mail path, plus copy-and-send by hand.
    private var mailUnavailableFallback: some View {
        VStack(alignment: .leading, spacing: Fx.Space.s) {
            if let email = spec.fallbackEmail {
                Text("Mail isn't set up on this phone. Share or copy the report and send it to \(email).")
                    .font(Fx.Font.footnote)
                    .foregroundStyle(Fx.Color.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            FxCopyButton(title: String(localized: "Copy report text", bundle: L10n.bundle, locale: L10n.locale), value: mailText)
        }
    }

    private func send() {
        Task { await model.send() }
    }

    private func sendByMail() {
        if MailComposer.canSendMail {
            isMailPresented = true
        } else {
            isSharePresented = true
        }
    }

    private var mailText: String {
        var text = MailFallback.body(model.draft, spec: spec)
        if let email = spec.fallbackEmail {
            text = String(localized: "To: \(email)", bundle: L10n.bundle, locale: L10n.locale) + "\n" + String(localized: "Subject: \(MailFallback.subject(model.draft, spec: spec))", bundle: L10n.bundle, locale: L10n.locale) + "\n\n" + text
        }
        return text
    }

    private var shareItems: [Any] {
        var items: [Any] = [mailText]
        if let data = model.draft.photoJPEG, let image = UIImage(data: data) {
            items.append(image)
        }
        return items
    }
}
