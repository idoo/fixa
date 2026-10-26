import FixaKit
import SwiftUI

struct HomeScreen: View {
    let spec: AdapterSpec
    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL

    private let columns = [
        GridItem(.flexible(), spacing: Fx.Space.m),
        GridItem(.flexible(), spacing: Fx.Space.m),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Fx.Space.xl) {
                VStack(alignment: .leading, spacing: Fx.Space.xs) {
                    Text(verbatim: "Fixa")
                        .font(Fx.Font.largeTitle)
                        .foregroundStyle(Fx.Color.ink)
                        .accessibilityAddTraits(.isHeader)
                    Text("Report a problem in \(placeName)")
                        .font(Fx.Font.body)
                        .foregroundStyle(Fx.Color.inkSoft)
                }

                if let emergency = spec.emergency {
                    urgentBanner(emergency)
                }

                VStack(alignment: .leading, spacing: Fx.Space.m) {
                    FxSectionHeader(String(localized: "What's wrong?"))
                    LazyVGrid(columns: columns, spacing: Fx.Space.m) {
                        ForEach(spec.tiles, id: \.id) { tile in
                            FxTile(
                                title: tile.title.resolve(),
                                systemImage: tile.symbol,
                                isSelected: model.draft.tileID == tile.id && !model.path.isEmpty
                            ) {
                                model.startReport(tile: tile)
                            }
                        }
                    }
                }

                Text("Sends to \(spec.municipality.name)'s e-service. Fixa is an independent app.")
                    .font(Fx.Font.footnote)
                    .foregroundStyle(Fx.Color.inkSoft)
            }
            .padding(.horizontal, Fx.Space.l)
            .padding(.vertical, Fx.Space.l)
        }
        .fxScreenBackground()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    model.path.append(.about)
                } label: {
                    Label("About", systemImage: "info.circle")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    model.path.append(.history)
                } label: {
                    Label("Sent reports", systemImage: "clock.arrow.circlepath")
                }
            }
        }
    }

    /// "Värmdö" from "Värmdö kommun": the subtitle stays descriptive.
    private var placeName: String {
        let name = spec.municipality.name
        for suffix in [" kommun", " Municipality"] where name.hasSuffix(suffix) {
            return String(name.dropLast(suffix.count))
        }
        return name
    }

    private func urgentBanner(_ emergency: AdapterSpec.Emergency) -> some View {
        let contact = EmergencyRouter.contact(for: .now, emergency: emergency)
        let digits = contact.phone.filter(\.isNumber)
        return FxBanner(
            kind: .warning,
            title: String(localized: "Urgent? No water or sewer blocked"),
            message: String(localized: "Call \(contact.title.resolve()), \(contact.phone). Don't wait for a reply here."),
            actionTitle: String(localized: "Call \(contact.phone)"),
            action: {
                if let url = URL(string: "tel:\(digits)") {
                    openURL(url)
                }
            }
        )
    }
}
