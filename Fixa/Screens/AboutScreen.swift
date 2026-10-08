import FixaKit
import SwiftUI

struct AboutScreen: View {
    let spec: AdapterSpec

    private static let repoURL = URL(string: "https://github.com/idoo/fixa")!

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Fx.Space.xl) {
                FxSectionHeader(
                    String(localized: "About Fixa"),
                    subtitle: String(localized: "A small app for reporting things that need fixing.")
                )

                FxCard {
                    Text("Open source")
                        .font(Fx.Font.headline)
                        .foregroundStyle(Fx.Color.ink)
                    Text("Fixa's code is open source under the EUPL-1.2 licence.")
                        .font(Fx.Font.body)
                        .foregroundStyle(Fx.Color.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                    Link(destination: Self.repoURL) {
                        Label("Source code on GitHub", systemImage: "arrow.up.forward.square")
                            .font(Fx.Font.callout.weight(.semibold))
                            .frame(minHeight: Fx.minTarget)
                    }
                    .foregroundStyle(Fx.Color.sea)
                }

                FxCard {
                    Text("Your data")
                        .font(Fx.Font.headline)
                        .foregroundStyle(Fx.Color.ink)
                    Text("Fixa has no server and no account. Your report goes straight from this phone to \(spec.municipality.name)'s e-service. Photos are re-saved without location data. Sent reports and your contact details are kept only on this phone.")
                        .font(Fx.Font.body)
                        .foregroundStyle(Fx.Color.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }

                FxCard {
                    Text("Good to know")
                        .font(Fx.Font.headline)
                        .foregroundStyle(Fx.Color.ink)
                    Text(spec.disclaimer.resolve())
                        .font(Fx.Font.body)
                        .foregroundStyle(Fx.Color.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Text("Version \(Self.version)")
                    .font(Fx.Font.footnote)
                    .foregroundStyle(Fx.Color.inkSoft)
            }
            .padding(Fx.Space.l)
        }
        .fxScreenBackground()
        .navigationTitle(Text("About"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private static var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "\(short) (\(build))"
    }
}
