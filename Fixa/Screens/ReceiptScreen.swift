import FixaKit
import SwiftUI

struct ReceiptScreen: View {
    let spec: AdapterSpec
    @Environment(AppModel.self) private var model
    @Environment(\.locale) private var locale
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

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
            FxBadge(systemImage: "clock.arrow.circlepath", fill: Fx.Color.categoryTint(nil), side: 64)
            VStack(spacing: Fx.Space.s) {
                Text("Waiting to send")
                    .font(Fx.Font.title)
                    .foregroundStyle(Fx.Color.ink)
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
                Text(model.isOnline
                    ? String(localized: "No answer from the e-service. Saved here; Fixa tries again soon.", bundle: L10n.bundle, locale: L10n.locale)
                    : String(localized: "You're offline. Saved here; Fixa sends it when you're back online.", bundle: L10n.bundle, locale: L10n.locale))
                    .font(Fx.Font.body)
                    .foregroundStyle(Fx.Color.ink2)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            sentReportsButton
        }
    }

    /// The final step went out but no confirmation came back. Never retried on its own, and no
    /// resend from here: sending again lives in the report's Sent reports detail, behind a warning.
    private func maybeSentContent(_ sent: SentReport) -> some View {
        VStack(spacing: Fx.Space.xl) {
            FxBadge(systemImage: "questionmark.circle", fill: Fx.Color.categoryTint(nil), side: 64)
            VStack(spacing: Fx.Space.s) {
                Text("May have been sent")
                    .font(Fx.Font.title)
                    .foregroundStyle(Fx.Color.ink)
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
                Text("No confirmation came back. It may well have reached \(spec.municipality.name).")
                    .font(Fx.Font.body)
                    .foregroundStyle(Fx.Color.ink2)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                // Asking about it is the row below ("Ask the kommun"), so no second pointer here.
                if sent.historyID.map({ model.wantsReply($0) }) == true {
                    Text("You asked for a reply, so the kommun answers by e-mail.")
                        .font(Fx.Font.callout)
                        .foregroundStyle(Fx.Color.ink2)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            VStack(spacing: Fx.Space.l) {
                ServiceCentreHelp(spec: spec, alignment: .center)
                sentReportsButton
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
                    kommunReceipt(sent.kommunMessage)
                    yourReport(sent)
                    KommunCaseContact(spec: spec, caseNumber: sent.caseNumber)
                    // The kommun's e-mail reply arrives outside Fixa, still in Swedish.
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
}

private extension ReceiptScreen {
    /// The kommun's own words from its receipt page, quoted and attributed; never Fixa speaking for it.
    /// In the app's language, with the exact Swedish behind "Show original".
    @ViewBuilder
    func kommunReceipt(_ message: String?) -> some View {
        if let message {
            FxCard {
                KommunTextView(
                    swedish: message,
                    spec: spec,
                    title: String(localized: "Värmdö kommun's receipt", bundle: L10n.bundle, locale: L10n.locale),
                    // The card already sets the quote apart; a rule inside it would be double chrome.
                    quoted: false
                )
            }
        } else {
            Text("Värmdö kommun has your report.")
                .font(Fx.Font.body)
                .foregroundStyle(Fx.Color.ink2)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// The resident's own words first; the exact Swedish the form got folded away under them.
    @ViewBuilder
    func yourReport(_ sent: SentReport) -> some View {
        let item = sent.historyID.flatMap { model.history.item(id: $0) }
        let ownWords = (sent.residentText ?? item?.description ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let filed = sent.filedText ?? item?.filedText
        if !ownWords.isEmpty || filed != nil {
            FxCard {
                VStack(alignment: .leading, spacing: Fx.Space.s) {
                    if !ownWords.isEmpty {
                        VStack(alignment: .leading, spacing: Fx.Space.xs) {
                            Text("What you wrote")
                                .font(Fx.Font.section)
                                .foregroundStyle(Fx.Color.ink2)
                            Text(ownWords)
                                .font(Fx.Font.body)
                                .foregroundStyle(Fx.Color.ink)
                                .fixedSize(horizontal: false, vertical: true)
                                .textSelection(.enabled)
                        }
                        .accessibilityElement(children: .combine)
                    }
                    if let filed {
                        FiledInSwedish(text: filed)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}
