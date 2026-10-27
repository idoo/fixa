import FixaKit
import SwiftUI

struct HomeScreen: View {
    let spec: AdapterSpec
    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// Two columns; one at accessibility sizes so titles keep whole words.
    private var columns: [GridItem] {
        let count = dynamicTypeSize.isAccessibilitySize ? 1 : 2
        return Array(repeating: GridItem(.flexible(), spacing: Fx.Space.m), count: count)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Fx.Space.l) {
                VStack(alignment: .leading, spacing: Fx.Space.xs) {
                    Text(verbatim: "Fixa")
                        .font(Fx.Font.largeTitle)
                        .foregroundStyle(Fx.Color.ink)
                        .accessibilityAddTraits(.isHeader)
                    Text("Report a problem in \(placeName) in a minute.")
                        .font(Fx.Font.body)
                        .foregroundStyle(Fx.Color.ink2)
                }

                LazyVGrid(columns: columns, spacing: Fx.Space.m) {
                    ForEach(Array(spec.tiles.enumerated()), id: \.element.id) { index, tile in
                        FxTile(
                            title: tile.title.resolve(),
                            systemImage: tile.symbol,
                            index: index,
                            isSelected: model.draft.tileID == tile.id && !model.path.isEmpty
                        ) {
                            model.startReport(tile: tile)
                        }
                    }
                }

                if let emergency = spec.emergency {
                    urgentRow(emergency)
                }

                Text("Independent app, not run by the municipality.")
                    .font(Fx.Font.footnote)
                    .foregroundStyle(Fx.Color.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, Fx.Space.l)
            .padding(.top, Fx.Space.xs)
            .padding(.bottom, Fx.Space.l)
        }
        .fxScreenBackground()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    model.path.append(.profile)
                } label: {
                    Label("Profile", systemImage: "person.crop.circle")
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

    /// Time-aware urgent line under the tiles; the number appears once, in the detail line.
    private func urgentRow(_ emergency: AdapterSpec.Emergency) -> some View {
        let contact = EmergencyRouter.contact(for: .now, emergency: emergency)
        let digits = contact.phone.filter(\.isNumber)
        return FxCallRow(
            title: String(localized: "No water or a blocked sewer?"),
            // Number first and unbreakable (NBSP, non-breaking hyphen): if the line wraps, only the name moves.
            detail: "\(contact.phone.replacingOccurrences(of: " ", with: "\u{00A0}").replacingOccurrences(of: "-", with: "\u{2011}")) · \(contact.title.resolve())"
        ) {
            if let url = URL(string: "tel:\(digits)") {
                openURL(url)
            }
        }
    }
}
