import FixaKit
import SwiftUI

struct AboutScreen: View {
    let spec: AdapterSpec

    private static let repoURL = URL(string: "https://github.com/idoo/fixa")!

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Fx.Space.l) {
                FxCard {
                    FxIconRow(
                        systemImage: "chevron.left.forwardslash.chevron.right",
                        text: String(localized: "Open source (EUPL-1.2) on GitHub"),
                        link: Self.repoURL
                    )
                    FxIconRow(
                        systemImage: "iphone",
                        text: String(localized: "No account, no server. Your data stays on this phone, and photos lose their location.")
                    )
                    FxIconRow(
                        systemImage: "building.columns",
                        text: String(localized: "Independent app, not part of \(spec.municipality.name).")
                    )
                }

                FxIconRow(
                    systemImage: "phone",
                    text: String(localized: "Call 112 if life or property is in danger.")
                )

                Text("Version \(Self.version)")
                    .font(Fx.Font.footnote)
                    .foregroundStyle(Fx.Color.inkSoft)
            }
            .padding(.horizontal, Fx.Space.l)
            .padding(.top, Fx.Space.s)
            .padding(.bottom, Fx.Space.l)
        }
        .fxScreenBackground()
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
