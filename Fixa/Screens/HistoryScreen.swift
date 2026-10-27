import FixaKit
import MapKit
import SwiftUI
import UIKit

struct HistoryScreen: View {
    let spec: AdapterSpec
    @Environment(AppModel.self) private var model

    var body: some View {
        Group {
            if model.history.items.isEmpty {
                emptyState
            } else {
                List {
                    Section {
                        ForEach(model.history.items) { item in
                            NavigationLink(value: Route.historyDetail(item.id)) {
                                HistoryRow(item: item, spec: spec)
                            }
                            .listRowBackground(Fx.Color.card)
                        }
                        .onDelete { offsets in
                            let ids = Set(offsets.map { model.history.items[$0].id })
                            model.history.delete(ids)
                        }
                    }
                    .listSectionMargins(.top, 0)
                }
                .scrollContentBackground(.hidden)
                // No dead gap under the nav bar: one 8 pt step, not the default grouped header space.
                .listSectionSpacing(.compact)
                .contentMargins(.top, Fx.Space.s, for: .scrollContent)
            }
        }
        .fxScreenBackground()
        .navigationTitle(Text("Sent reports"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // Deleting without a swipe, for Voice Control and Switch Control.
            if !model.history.items.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    EditButton()
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: Fx.Space.l) {
            FxBadge(systemImage: "tray", fill: Fx.Color.Pastel.sky, side: 64)
            Text("No reports yet.")
                .font(Fx.Font.title)
                .foregroundStyle(Fx.Color.ink)
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
            FxPrimaryButton(title: String(localized: "Report a problem", bundle: L10n.bundle, locale: L10n.locale), systemImage: "plus") {
                model.path = []
            }
            .padding(.top, Fx.Space.s)
        }
        .padding(Fx.Space.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct HistoryRow: View {
    let item: HistoryItem
    let spec: AdapterSpec
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.locale) private var locale
    @ScaledMetric(relativeTo: .headline) private var thumbnailSide: CGFloat = 56

    var body: some View {
        // Thumbnail above the text at accessibility sizes, so the text keeps the full width.
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Fx.Space.s))
            : AnyLayout(HStackLayout(spacing: Fx.Space.m))
        layout {
            HistoryThumbnail(item: item, spec: spec, side: min(thumbnailSide, 80))
            VStack(alignment: .leading, spacing: Fx.Space.xs) {
                Text(spec.tile(id: item.tileID)?.title.resolve(L10n.locale) ?? String(localized: "Report", bundle: L10n.bundle, locale: L10n.locale))
                    .font(Fx.Font.headline)
                    .foregroundStyle(Fx.Color.ink)
                Text(item.locationText.isEmpty ? item.description : item.locationText)
                    .font(Fx.Font.callout)
                    .foregroundStyle(Fx.Color.ink2)
                    .lineLimit(3)
                Text(item.date.formatted(.dateTime.day().month().year().locale(locale)))
                    .font(Fx.Font.footnote)
                    .foregroundStyle(Fx.Color.ink2)
            }
        }
        .padding(.vertical, Fx.Space.xs)
        .accessibilityElement(children: .combine)
    }
}

/// Decorative in list rows; pass `accessibilityLabel` where the photo is content (the detail screen).
private struct HistoryThumbnail: View {
    let item: HistoryItem
    let spec: AdapterSpec
    let side: CGFloat
    var accessibilityLabel: String? = nil

    var body: some View {
        Group {
            if let data = item.thumbnail, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: spec.tile(id: item.tileID)?.symbol ?? "doc.text")
                    .font(Fx.Font.title)
                    .foregroundStyle(Fx.Color.onPastel)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Fx.Color.Pastel.sky)
            }
        }
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: Fx.Radius.s, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Fx.Radius.s, style: .continuous).strokeBorder(Fx.Color.line, lineWidth: Fx.Border.hairline))
        .accessibilityElement()
        .accessibilityLabel(Text(accessibilityLabel ?? ""))
        .accessibilityAddTraits(.isImage)
        .accessibilityHidden(accessibilityLabel == nil)
    }
}

struct HistoryDetailScreen: View {
    let spec: AdapterSpec
    let itemID: UUID
    @Environment(AppModel.self) private var model
    @Environment(\.locale) private var locale
    @State private var isRemoveConfirmPresented = false

    var body: some View {
        let item = model.history.item(id: itemID)
        Group {
            if let item {
                ScrollView {
                    VStack(alignment: .leading, spacing: Fx.Space.xl) {
                        FxSectionHeader(
                            title(for: item),
                            subtitle: item.date.formatted(.dateTime.day().month(.wide).year().hour().minute().locale(locale))
                        )
                        FxCard {
                            if let caseNumber = item.caseNumber {
                                VStack(alignment: .leading, spacing: Fx.Space.s) {
                                    field(String(localized: "Case number", bundle: L10n.bundle, locale: L10n.locale), value: caseNumber)
                                    FxCopyButton(title: String(localized: "Copy case number", bundle: L10n.bundle, locale: L10n.locale), value: caseNumber)
                                }
                            } else {
                                field(String(localized: "Case number", bundle: L10n.bundle, locale: L10n.locale), value: String(localized: "Not given by the e-service", bundle: L10n.bundle, locale: L10n.locale))
                            }
                            field(String(localized: "Place", bundle: L10n.bundle, locale: L10n.locale), value: placeText(for: item))
                            if let lat = item.latitude, let lng = item.longitude {
                                let center = CLLocationCoordinate2D(latitude: lat, longitude: lng)
                                Map(initialPosition: .region(MKCoordinateRegion(
                                    center: center,
                                    latitudinalMeters: 400,
                                    longitudinalMeters: 400
                                )), interactionModes: []) {
                                    Marker(placeText(for: item), coordinate: center)
                                        .tint(Fx.Color.sea)
                                }
                                .frame(height: 140)
                                .clipShape(RoundedRectangle(cornerRadius: Fx.Radius.s, style: .continuous))
                                .fxOutline(RoundedRectangle(cornerRadius: Fx.Radius.s, style: .continuous), fill: .clear)
                                .allowsHitTesting(false)
                                .accessibilityHidden(true)
                            }
                            field(String(localized: "Description", bundle: L10n.bundle, locale: L10n.locale), value: item.description)
                            if item.thumbnail != nil {
                                HistoryThumbnail(
                                    item: item,
                                    spec: spec,
                                    side: 120,
                                    accessibilityLabel: String(localized: "Attached photo", bundle: L10n.bundle, locale: L10n.locale)
                                )
                            }
                        }
                        FxSecondaryButton(title: String(localized: "Remove from this phone", bundle: L10n.bundle, locale: L10n.locale), systemImage: "trash") {
                            isRemoveConfirmPresented = true
                        }
                    }
                    .padding(.horizontal, Fx.Space.l)
                    .padding(.top, Fx.Space.s)
                    .padding(.bottom, Fx.Space.l)
                }
            } else {
                ContentUnavailableView("Report not found", systemImage: "questionmark.folder")
            }
        }
        .fxScreenBackground()
        .navigationTitle(Text(item.map(title(for:)) ?? String(localized: "Report", bundle: L10n.bundle, locale: L10n.locale)))
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            Text("Remove this report from this phone?"),
            isPresented: $isRemoveConfirmPresented,
            titleVisibility: .visible
        ) {
            Button(role: .destructive, action: remove) {
                Text("Remove from this phone")
            }
        } message: {
            Text("It disappears from Sent reports in Fixa. The report itself stays with \(spec.municipality.name).")
        }
    }

    private func title(for item: HistoryItem) -> String {
        spec.tile(id: item.tileID)?.title.resolve(L10n.locale) ?? String(localized: "Report", bundle: L10n.bundle, locale: L10n.locale)
    }

    private func remove() {
        model.history.delete([itemID])
        if model.path.last == .historyDetail(itemID) {
            model.path.removeLast()
        }
    }

    /// Address or place text only; never coordinates.
    private func placeText(for item: HistoryItem) -> String {
        let text = item.locationText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty { return text }
        return item.latitude != nil ? String(localized: "Pin on the map", bundle: L10n.bundle, locale: L10n.locale) : "–"
    }

    private func field(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: Fx.Space.xs) {
            Text(title)
                .font(Fx.Font.subheadline)
                .foregroundStyle(Fx.Color.ink2)
            Text(value)
                .font(Fx.Font.body)
                .foregroundStyle(Fx.Color.ink)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}
