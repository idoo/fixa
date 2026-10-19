import FixaKit
import SwiftUI

/// "What Fixa stores": plain sentences, with where each thing lives as small print.
struct PrivacyScreen: View {
    let spec: AdapterSpec

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Fx.Space.l) {
                FxCard {
                    item(
                        String(localized: "Your contact details: on this phone until you delete them."),
                        storage: "UserDefaults fixa.contact"
                    )
                    FxDivider()
                    item(
                        String(localized: "Your unsent report (text, place, up to 3 photos): until you send or discard it."),
                        storage: "UserDefaults fixa.draft · Caches/fixa-draft"
                    )
                    FxDivider()
                    item(
                        String(localized: "Sent reports (type, text, place, small photo, case number): on this phone until you delete them."),
                        storage: "Application Support/Fixa/history.json"
                    )
                    FxDivider()
                    item(
                        String(localized: "Your settings (language, text size)."),
                        storage: "UserDefaults fixa.language · fixa.display · fixa.rememberDetails · fixa.onboarded"
                    )
                }

                FxCard {
                    item(String(localized: "Fixa has no account, server or statistics. Photos lose their location before they are sent."), storage: nil)
                    FxDivider()
                    item(String(localized: "These are included in your iPhone backup."), storage: nil)
                    FxDivider()
                    item(
                        String(localized: "Once in a while Fixa downloads an updated description of the municipality's form from GitHub. Nothing about you is sent."),
                        storage: "raw.githubusercontent.com/idoo/fixa · Application Support/Adapters"
                    )
                    FxDivider()
                    item(
                        String(localized: "Reports already sent belong to \(spec.municipality.name); ask them to change or delete one. Reports sent by e-mail also stay in your Mail app."),
                        storage: nil
                    )
                }
            }
            .padding(Fx.Space.l)
        }
        .fxScreenBackground()
        .navigationTitle(Text("What Fixa stores"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func item(_ text: String, storage: String?) -> some View {
        VStack(alignment: .leading, spacing: Fx.Space.xs) {
            Text(text)
                .font(Fx.Font.body)
                .foregroundStyle(Fx.Color.ink)
                .fixedSize(horizontal: false, vertical: true)
            if let storage {
                // File and key names stay as they are in every language, left to right.
                Text(verbatim: storage)
                    .font(Fx.Font.footnote.monospaced())
                    .foregroundStyle(Fx.Color.ink2)
                    .environment(\.layoutDirection, .leftToRight)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel(Text("Stored in \(storage)"))
            }
        }
        .frame(maxWidth: .infinity, minHeight: Fx.minTarget, alignment: .leading)
        .padding(.vertical, Fx.Space.xs)
        .accessibilityElement(children: .combine)
    }
}
