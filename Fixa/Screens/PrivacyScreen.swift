import FixaKit
import SwiftUI

/// "What Fixa stores": four short lines, nothing technical.
struct PrivacyScreen: View {
    let spec: AdapterSpec

    var body: some View {
        ScrollView {
            FxCard {
                FxIconRow(
                    systemImage: "iphone",
                    text: String(localized: "Your details, drafts and sent reports stay on this phone. No account, no tracking.", bundle: L10n.bundle, locale: L10n.locale)
                )
                FxDivider()
                FxIconRow(
                    systemImage: "paperplane",
                    text: String(localized: "A report goes only to the kommun, when you press Send. Photos lose their location first.", bundle: L10n.bundle, locale: L10n.locale)
                )
                FxDivider()
                FxIconRow(
                    systemImage: "doc.text",
                    text: String(localized: "Sent reports become public records. Leave out faces, number plates and names.", bundle: L10n.bundle, locale: L10n.locale)
                )
                FxDivider()
                FxIconRow(
                    systemImage: "trash",
                    text: String(localized: "Delete everything in Settings. To change a sent report, contact \(spec.municipality.name).", bundle: L10n.bundle, locale: L10n.locale)
                )
            }
            .padding(.horizontal, Fx.Space.l)
            .padding(.top, Fx.Space.s)
            .padding(.bottom, Fx.Space.l)
        }
        .fxScreenBackground()
        .navigationTitle(Text("What Fixa stores"))
        .navigationBarTitleDisplayMode(.inline)
    }
}
