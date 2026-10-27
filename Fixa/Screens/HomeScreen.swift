import FixaKit
import SwiftUI

struct HomeScreen: View {
    let spec: AdapterSpec
    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// Two columns; one at accessibility sizes so titles keep whole words.
    private var columns: Int {
        dynamicTypeSize.isAccessibilitySize ? 1 : 2
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Fx.Space.l) {
                let status = model.adapterStatus
                if status.state != .ok {
                    FxBanner(
                        kind: .warning,
                        title: String(localized: "The municipality's e-service has changed", bundle: L10n.bundle, locale: L10n.locale),
                        message: status.message?.resolve(L10n.locale)
                            ?? String(localized: "Fixa is an independent app. We are updating it. Your report is saved, and you can still send it by email.", bundle: L10n.bundle, locale: L10n.locale)
                    )
                }
                if let notice = model.outboxNotice {
                    Button {
                        model.path = [.history]
                    } label: {
                        FxBanner(kind: .info, title: notice.title, message: notice.message)
                    }
                    .buttonStyle(FxPressStyle())
                    .accessibilityHint(Text("Opens Sent reports"))
                    .accessibilityIdentifier("home.outboxBanner")
                }
                // No app name on Home: the icon already says "Fixa"; the line says what to do.
                Text("Report a problem in \(placeName) in a minute.")
                    .font(Fx.Font.body)
                    .foregroundStyle(Fx.Color.ink2)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .accessibilityAddTraits(.isHeader)

                FxTileGrid(columns: columns, spacing: Fx.Space.m) {
                    ForEach(Array(spec.tiles.enumerated()), id: \.element.id) { index, tile in
                        FxTile(
                            title: tile.title.resolve(L10n.locale),
                            systemImage: tile.symbol,
                            index: index,
                            isSelected: model.draft.tileID == tile.id && !model.path.isEmpty
                        ) {
                            model.startReport(tile: tile)
                        }
                        .accessibilityIdentifier("home.tile.\(tile.id)")
                    }
                }

                if let emergency = spec.emergency {
                    urgentRow(emergency)
                }

                Text("Independent app, not run by the municipality.")
                    .font(Fx.Font.footnote)
                    .foregroundStyle(Fx.Color.ink2)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
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
                    model.path.append(.settings)
                } label: {
                    Label("Settings", systemImage: "gearshape")
                        .labelStyle(.titleAndIcon)
                }
                .accessibilityIdentifier("home.settings")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    model.path.append(.history)
                } label: {
                    Label("Sent reports", systemImage: "clock.arrow.circlepath")
                        .labelStyle(.titleAndIcon)
                }
                .accessibilityIdentifier("home.history")
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
        // Number first and unbreakable (NBSP, non-breaking hyphen): if the line wraps, only the name moves.
        let number = contact.phone.replacingOccurrences(of: " ", with: "\u{00A0}").replacingOccurrences(of: "-", with: "\u{2011}")
        return FxCallRow(
            title: String(localized: "No water or a blocked sewer?", bundle: L10n.bundle, locale: L10n.locale),
            detail: "\(number.ltrIsolated) · \(contact.title.resolve(L10n.locale))",
            accessibilityValue: "\(contact.phone), \(contact.title.resolve(L10n.locale))"
        ) {
            if let url = URL(string: "tel:\(digits)") {
                openURL(url)
            }
        }
    }
}
