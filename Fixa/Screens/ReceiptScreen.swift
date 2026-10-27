import FixaKit
import SwiftUI

struct ReceiptScreen: View {
    let spec: AdapterSpec
    @Environment(AppModel.self) private var model
    @Environment(\.locale) private var locale
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.openURL) private var openURL

    var body: some View {
        let sent = model.sent ?? SentReport(caseNumber: nil, date: .now, isDryRun: false)
        GeometryReader { proxy in
            ScrollView {
                content(sent)
                    .padding(Fx.Space.l)
                    // Centre the block in the visible height when it fits; scroll when it doesn't.
                    .frame(maxWidth: .infinity, minHeight: proxy.size.height, alignment: .center)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .fxScreenBackground()
        .fxBottomBar {
            FxPrimaryButton(title: String(localized: "Done", bundle: L10n.bundle, locale: L10n.locale), systemImage: "checkmark") {
                model.finish()
            }
        }
        .navigationBarBackButtonHidden(true)
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func content(_ sent: SentReport) -> some View {
        switch sent.outcome {
        case .sent: sentContent(sent)
        case .waiting: waitingContent(sent)
        case .maybeSent: maybeSentContent(sent)
        }
    }

    /// Saved in the outbox; Fixa sends it on its own. Turns into the sent receipt when it goes through.
    private func waitingContent(_ sent: SentReport) -> some View {
        VStack(spacing: Fx.Space.xl) {
            FxBadge(systemImage: "clock.arrow.circlepath", fill: Fx.Color.Pastel.sky, side: 64)
            VStack(spacing: Fx.Space.s) {
                Text("Waiting to send")
                    .font(Fx.Font.title)
                    .foregroundStyle(Fx.Color.ink)
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
                Text(model.isOnline
                    ? String(localized: "The e-service didn't answer. Your report is saved on this phone, and Fixa tries again in a little while.", bundle: L10n.bundle, locale: L10n.locale)
                    : String(localized: "Your phone seems to be offline. Your report is saved on this phone, and Fixa sends it when you're back online.", bundle: L10n.bundle, locale: L10n.locale))
                    .font(Fx.Font.body)
                    .foregroundStyle(Fx.Color.ink2)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Text("You can close Fixa. You'll find the report under Sent reports.")
                    .font(Fx.Font.callout)
                    .foregroundStyle(Fx.Color.ink2)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            sentReportsButton
        }
    }

    /// The final step went out but no confirmation came back. Never retried on its own, and no
    /// resend from here: the advice is to wait and check. Sending again lives in the report's
    /// Sent reports detail, behind a warning.
    private func maybeSentContent(_ sent: SentReport) -> some View {
        VStack(spacing: Fx.Space.xl) {
            FxBadge(systemImage: "questionmark.circle", fill: Fx.Color.Pastel.sky, side: 64)
            VStack(spacing: Fx.Space.s) {
                Text("May have been sent")
                    .font(Fx.Font.title)
                    .foregroundStyle(Fx.Color.ink)
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
                Text("The connection dropped just as the report went out, so Fixa didn't see a confirmation. It may well have reached \(spec.municipality.name).")
                    .font(Fx.Font.body)
                    .foregroundStyle(Fx.Color.ink2)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Text(sent.historyID.map { model.wantsReply($0) } == true
                    ? String(localized: "Wait a day and check your e-mail for a confirmation from \(spec.municipality.name).", bundle: L10n.bundle, locale: L10n.locale)
                    : String(localized: "Wait a day and see if the problem gets fixed. If you're unsure, call \(spec.municipality.name) and ask.", bundle: L10n.bundle, locale: L10n.locale))
                    .font(Fx.Font.callout)
                    .foregroundStyle(Fx.Color.ink2)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(spacing: Fx.Space.l) {
                if let call = serviceCentreRow {
                    call
                }
                if let id = sent.historyID, let text = model.reportText(for: id) {
                    FxCopyButton(title: String(localized: "Copy report text", bundle: L10n.bundle, locale: L10n.locale), value: text)
                }
                sentReportsButton
            }
        }
    }

    /// The municipality's service centre, from the adapter's contacts: the person to ask whether
    /// the report arrived. Nil when the adapter lists none.
    private var serviceCentreRow: FxCallRow? {
        guard let contact = spec.emergency?.contacts.first(where: { $0.id == "servicecenter" }) else { return nil }
        let digits = contact.phone.filter(\.isNumber)
        // Number first and unbreakable (NBSP, non-breaking hyphen): if the line wraps, only the name moves.
        let number = contact.phone.replacingOccurrences(of: " ", with: "\u{00A0}").replacingOccurrences(of: "-", with: "\u{2011}")
        return FxCallRow(
            title: String(localized: "Ask if it arrived", bundle: L10n.bundle, locale: L10n.locale),
            detail: "\(number.ltrIsolated) · \(contact.title.resolve(L10n.locale))",
            accessibilityValue: "\(contact.phone), \(contact.title.resolve(L10n.locale))"
        ) {
            if let url = URL(string: "tel:\(digits)") {
                openURL(url)
            }
        }
    }

    private var sentReportsButton: some View {
        FxSecondaryButton(title: String(localized: "Sent reports", bundle: L10n.bundle, locale: L10n.locale), systemImage: "clock.arrow.circlepath") {
            model.finish()
            model.path = [.history]
        }
    }

    private func sentContent(_ sent: SentReport) -> some View {
        VStack(spacing: Fx.Space.xl) {
            if sent.isDryRun {
                FxBanner(
                    kind: .info,
                    title: String(localized: "Test run finished", bundle: L10n.bundle, locale: L10n.locale),
                    message: String(localized: "Fixa reached the last step and stopped. Nothing was submitted.", bundle: L10n.bundle, locale: L10n.locale)
                )
            } else {
                VStack(spacing: Fx.Space.s) {
                    FxStatusStamp(caseNumber: sent.caseNumber)
                    // The stamp caps its text size; at accessibility sizes this plain line repeats the
                    // number so it scales all the way. Otherwise the stamp alone shows it (no duplicate).
                    if let caseNumber = sent.caseNumber, dynamicTypeSize.isAccessibilitySize {
                        Text("Case number \(caseNumber.ltrIsolated)")
                            .font(Fx.Font.headline)
                            .foregroundStyle(Fx.Color.ink)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                    }
                }
            }

            VStack(spacing: Fx.Space.s) {
                Text(sent.isDryRun ? String(localized: "Not sent", bundle: L10n.bundle, locale: L10n.locale) : String(localized: "Sent to \(spec.municipality.name)", bundle: L10n.bundle, locale: L10n.locale))
                    .font(Fx.Font.title)
                    .foregroundStyle(Fx.Color.ink)
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
                Text(sent.date, format: .dateTime.day().month(.wide).year().hour().minute())
                    .font(Fx.Font.callout)
                    .foregroundStyle(Fx.Color.ink2)
                    .multilineTextAlignment(.center)
                if !sent.isDryRun, let caseNumber = sent.caseNumber {
                    FxCopyButton(title: String(localized: "Copy case number", bundle: L10n.bundle, locale: L10n.locale), value: caseNumber)
                        .padding(.top, Fx.Space.s)
                }
            }

            if !sent.isDryRun {
                VStack(spacing: Fx.Space.l) {
                    Text(nextStep)
                        .font(Fx.Font.body)
                        .foregroundStyle(Fx.Color.ink2)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                    if model.draft.wantsFeedback, locale.language.languageCode != .swedish {
                        Text("The reply will be in Swedish. You can open it in Translate.")
                            .font(Fx.Font.callout)
                            .foregroundStyle(Fx.Color.ink2)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    sentReportsButton
                }
            }
        }
    }

    private var nextStep: String {
        model.draft.wantsFeedback
            ? String(localized: "They pass it to the right team and reply by e-mail.", bundle: L10n.bundle, locale: L10n.locale)
            : String(localized: "They pass it to the right team.", bundle: L10n.bundle, locale: L10n.locale)
    }
}
