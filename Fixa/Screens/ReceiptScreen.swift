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

    private func content(_ sent: SentReport) -> some View {
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
                    FxSecondaryButton(title: String(localized: "Sent reports", bundle: L10n.bundle, locale: L10n.locale), systemImage: "clock.arrow.circlepath") {
                        model.finish()
                        model.path = [.history]
                    }
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
