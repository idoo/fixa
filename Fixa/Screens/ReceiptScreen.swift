import FixaKit
import SwiftUI

struct ReceiptScreen: View {
    let spec: AdapterSpec
    @Environment(AppModel.self) private var model

    var body: some View {
        let sent = model.sent ?? SentReport(caseNumber: nil, date: .now, isDryRun: false)
        ScrollView {
            VStack(spacing: Fx.Space.xl) {
                if sent.isDryRun {
                    FxBanner(
                        kind: .info,
                        title: String(localized: "Test run finished"),
                        message: String(localized: "Fixa reached the last step and stopped. Nothing was submitted.")
                    )
                } else {
                    FxStatusStamp(caseNumber: sent.caseNumber)
                        .padding(.vertical, Fx.Space.xl)
                }

                VStack(spacing: Fx.Space.s) {
                    Text(sent.isDryRun ? String(localized: "Not sent") : String(localized: "Sent to \(spec.municipality.name)"))
                        .font(Fx.Font.title)
                        .foregroundStyle(Fx.Color.ink)
                        .multilineTextAlignment(.center)
                    Text(sent.date, format: .dateTime.day().month(.wide).year().hour().minute())
                        .font(Fx.Font.callout)
                        .foregroundStyle(Fx.Color.inkSoft)
                    if let caseNumber = sent.caseNumber {
                        Text("Case number \(caseNumber)")
                            .font(Fx.Font.callout)
                            .foregroundStyle(Fx.Color.inkSoft)
                            .textSelection(.enabled)
                    }
                }

                if !sent.isDryRun {
                    FxCard {
                        Text("What happens next")
                            .font(Fx.Font.headline)
                            .foregroundStyle(Fx.Color.ink)
                        Text("The municipality reviews the report and sends it to the right team. If you asked for a reply, they will contact you by e-mail.")
                            .font(Fx.Font.body)
                            .foregroundStyle(Fx.Color.inkSoft)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("You'll find this report under Sent reports.")
                            .font(Fx.Font.footnote)
                            .foregroundStyle(Fx.Color.inkSoft)
                    }
                }

                FxPrimaryButton(title: String(localized: "Done"), systemImage: "checkmark") {
                    model.finish()
                }
            }
            .padding(Fx.Space.l)
        }
        .fxScreenBackground()
        .navigationBarBackButtonHidden(true)
        .navigationBarTitleDisplayMode(.inline)
    }
}
