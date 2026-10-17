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
    }

    private var emptyState: some View {
        VStack(spacing: Fx.Space.l) {
            FxBadge(systemImage: "tray", fill: Fx.Color.Pastel.sky, side: 64)
            Text("No reports yet.")
                .font(Fx.Font.title)
                .foregroundStyle(Fx.Color.ink)
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
            FxPrimaryButton(title: String(localized: "Report a problem"), systemImage: "plus") {
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

    var body: some View {
        HStack(spacing: Fx.Space.m) {
            HistoryThumbnail(item: item, spec: spec, side: 56)
            VStack(alignment: .leading, spacing: Fx.Space.xs) {
                Text(spec.tile(id: item.tileID)?.title.resolve() ?? String(localized: "Report"))
                    .font(Fx.Font.headline)
                    .foregroundStyle(Fx.Color.ink)
                Text(item.locationText.isEmpty ? item.description : item.locationText)
                    .font(Fx.Font.callout)
                    .foregroundStyle(Fx.Color.ink2)
                    .lineLimit(1)
                Text(item.date, format: .dateTime.day().month().year())
                    .font(Fx.Font.footnote)
                    .foregroundStyle(Fx.Color.ink2)
            }
        }
        .padding(.vertical, Fx.Space.xs)
        .accessibilityElement(children: .combine)
    }
}

private struct HistoryThumbnail: View {
    let item: HistoryItem
    let spec: AdapterSpec
    let side: CGFloat

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
        .accessibilityHidden(true)
    }
}

struct HistoryDetailScreen: View {
    let spec: AdapterSpec
    let itemID: UUID
    @Environment(AppModel.self) private var model

    var body: some View {
        Group {
            if let item = model.history.item(id: itemID) {
                ScrollView {
                    VStack(alignment: .leading, spacing: Fx.Space.xl) {
                        FxSectionHeader(
                            spec.tile(id: item.tileID)?.title.resolve() ?? String(localized: "Report"),
                            subtitle: item.date.formatted(.dateTime.day().month(.wide).year().hour().minute())
                        )
                        FxCard {
                            if let caseNumber = item.caseNumber {
                                VStack(alignment: .leading, spacing: Fx.Space.s) {
                                    field(String(localized: "Case number"), value: caseNumber)
                                    FxCopyButton(title: String(localized: "Copy case number"), value: caseNumber)
                                }
                            } else {
                                field(String(localized: "Case number"), value: String(localized: "Not given by the e-service"))
                            }
                            field(String(localized: "Place"), value: placeText(for: item))
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
                            field(String(localized: "Description"), value: item.description)
                            if item.thumbnail != nil {
                                HistoryThumbnail(item: item, spec: spec, side: 120)
                            }
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
        .navigationBarTitleDisplayMode(.inline)
    }

    /// Address or place text only; never coordinates.
    private func placeText(for item: HistoryItem) -> String {
        let text = item.locationText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty { return text }
        return item.latitude != nil ? String(localized: "Pin on the map") : "–"
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
