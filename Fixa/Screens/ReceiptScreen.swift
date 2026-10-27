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
    /// resend from here: sending again lives in the report's Sent reports detail, behind a warning.
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
                    ? String(localized: "You asked for a reply, so the kommun answers by e-mail. If you're unsure whether it arrived, ask the servicecenter.", bundle: L10n.bundle, locale: L10n.locale)
                    : String(localized: "If you're unsure whether it arrived, ask the servicecenter.", bundle: L10n.bundle, locale: L10n.locale))
                    .font(Fx.Font.callout)
                    .foregroundStyle(Fx.Color.ink2)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
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
    @ViewBuilder
    func kommunReceipt(_ message: String?) -> some View {
        if let message {
            VStack(alignment: .leading, spacing: Fx.Space.xs) {
                Text("Värmdö kommun's receipt")
                    .font(Fx.Font.footnote.weight(.semibold))
                    .foregroundStyle(Fx.Color.ink2)
                Text(message)
                    .font(Fx.Font.body)
                    .foregroundStyle(Fx.Color.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                    .environment(\.locale, Locale(identifier: "sv_SE"))
            }
            .padding(.leading, Fx.Space.m)
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(Fx.Color.line)
                    .frame(width: 2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
        } else {
            Text("Värmdö kommun has your report.")
                .font(Fx.Font.body)
                .foregroundStyle(Fx.Color.ink2)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Who to ask whether an unconfirmed report arrived: the kommun's servicecenter. A call button
/// only while it is open (per the adapter's hours), otherwise its opening hours. Empty when the
/// adapter lists no servicecenter.
struct ServiceCentreHelp: View {
    let spec: AdapterSpec
    var alignment: TextAlignment = .leading
    @Environment(\.openURL) private var openURL

    private static let contactID = "servicecenter"

    var body: some View {
        if let emergency = spec.emergency,
           let contact = emergency.contacts.first(where: { $0.id == Self.contactID }) {
            // Re-evaluated each minute so the button disappears at closing time.
            TimelineView(.everyMinute) { context in
                if EmergencyRouter.isOpen(contactID: Self.contactID, at: context.date, emergency: emergency) {
                    callRow(contact)
                } else if let hours = Self.hoursText(emergency) {
                    Text(String(localized: "\(contact.title.resolve(L10n.locale)) is open \(hours).", bundle: L10n.bundle, locale: L10n.locale))
                        .font(Fx.Font.callout)
                        .foregroundStyle(Fx.Color.ink2)
                        .multilineTextAlignment(alignment)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func callRow(_ contact: AdapterSpec.EmergencyContact) -> FxCallRow {
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

    /// "Mon–Thu 08:00–17:00, Fri 08:00–13:00" from the adapter's rules for the servicecenter.
    static func hoursText(_ emergency: AdapterSpec.Emergency) -> String? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = L10n.locale
        let symbols = calendar.shortStandaloneWeekdaySymbols
        // ISO 1 = Monday … 7 = Sunday; the symbols start at Sunday.
        func day(_ iso: Int) -> String { symbols[iso % 7] }
        let parts = emergency.rules.filter { $0.contactID == contactID }.compactMap { rule -> String? in
            let days = rule.isoWeekdays.filter { (1...7).contains($0) }.sorted()
            guard let first = days.first, let last = days.last else { return nil }
            let isRun = days.count > 1 && last - first == days.count - 1
            let dayText = isRun ? "\(day(first))–\(day(last))" : days.map(day).joined(separator: ", ")
            let time = rule.from.map { "\($0)–\(rule.until)" }
                ?? String(localized: "until \(rule.until)", bundle: L10n.bundle, locale: L10n.locale)
            return "\(dayText) \(time)"
        }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }
}
