import FixaKit
import SwiftUI

/// "What Fixa stores": three short human sentences, nothing technical.
struct PrivacyScreen: View {
    let spec: AdapterSpec

    var body: some View {
        ScrollView {
            FxCard {
                VStack(alignment: .leading, spacing: Fx.Space.m) {
                    paragraph(String(localized: "Everything stays on your phone: your details, drafts and the reports you've sent. No account, no server, no tracking.", bundle: L10n.bundle, locale: L10n.locale))
                    paragraph(String(localized: "A report goes only to the municipality, and only when you press Send. Photos lose their location first.", bundle: L10n.bundle, locale: L10n.locale))
                    paragraph(String(localized: "You can delete everything in Settings. To change or remove a report you've already sent, contact \(spec.municipality.name).", bundle: L10n.bundle, locale: L10n.locale))
                }
                .padding(.vertical, Fx.Space.xs)
            }
            .padding(Fx.Space.l)
        }
        .fxScreenBackground()
        .navigationTitle(Text("What Fixa stores"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func paragraph(_ text: String) -> some View {
        Text(text)
            .font(Fx.Font.body)
            .foregroundStyle(Fx.Color.ink)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
    }
}
