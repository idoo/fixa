import FixaKit
import SwiftUI

struct AboutScreen: View {
    let spec: AdapterSpec
    @Environment(AppModel.self) private var model
    @State private var developerReport: DeveloperReport?

    private static let repoURL = URL(string: "https://github.com/idoo/fixa")!

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Fx.Space.l) {
                FxCard {
                    FxIconRow(
                        systemImage: "chevron.left.forwardslash.chevron.right",
                        text: String(localized: "Open source (EUPL-1.2) on GitHub", bundle: L10n.bundle, locale: L10n.locale),
                        link: Self.repoURL
                    )
                    FxDivider()
                    FxIconRow(
                        systemImage: "iphone",
                        text: String(localized: "No account, no server. Your data stays on this phone, and photos lose their location.", bundle: L10n.bundle, locale: L10n.locale)
                    )
                    FxDivider()
                    FxIconRow(
                        systemImage: "building.columns",
                        text: String(localized: "Independent app, not part of \(spec.municipality.name).", bundle: L10n.bundle, locale: L10n.locale)
                    )
                }

                FxCard {
                    SettingsNavRow(
                        systemImage: "questionmark.circle",
                        title: String(localized: "How Fixa works", bundle: L10n.bundle, locale: L10n.locale),
                        value: nil
                    ) {
                        model.showOnboarding()
                    }
                }

                FxCard {
                    FxIconRow(
                        systemImage: "envelope",
                        text: String(localized: "Questions about Fixa? Write to the developer (\(DeveloperReport.address)), not the kommun.", bundle: L10n.bundle, locale: L10n.locale)
                    ) {
                        developerReport = DeveloperReport(spec: spec)
                    }
                    .accessibilityIdentifier("about.developer")
                    if let contact = spec.contact {
                        FxDivider()
                        FxIconRow(
                            systemImage: "building.columns",
                            text: String(localized: "Questions about your report? Ask the kommun on its website.", bundle: L10n.bundle, locale: L10n.locale)
                        ) {
                            KommunWeb.open(contact.pageURL, spec: spec)
                        }
                        .accessibilityIdentifier("about.kommunContact")
                    }
                }

                FxCard {
                    FxIconRow(
                        systemImage: "phone",
                        text: String(localized: "Call 112 if life or property is in danger.", bundle: L10n.bundle, locale: L10n.locale)
                    )
                }

                Text("Version \(Self.version)")
                    .font(Fx.Font.footnote)
                    .foregroundStyle(Fx.Color.ink2)
            }
            .padding(.horizontal, Fx.Space.l)
            .padding(.top, Fx.Space.s)
            .padding(.bottom, Fx.Space.l)
        }
        .fxScreenBackground()
        .developerReport($developerReport)
        .navigationTitle(Text("About Fixa"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private static var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "\(short) (\(build))"
    }
}
