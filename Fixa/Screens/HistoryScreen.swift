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
                ContentUnavailableView(
                    "No reports yet",
                    systemImage: "tray",
                    description: Text("Reports you send are kept here, on this phone only.")
                )
            } else {
                List {
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
                .scrollContentBackground(.hidden)
            }
        }
        .fxScreenBackground()
        .navigationTitle(Text("Sent reports"))
        .navigationBarTitleDisplayMode(.inline)
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
                    .foregroundStyle(Fx.Color.inkSoft)
                    .lineLimit(1)
                Text(item.date, format: .dateTime.day().month().year())
                    .font(Fx.Font.footnote)
                    .foregroundStyle(Fx.Color.inkSoft)
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
                    .foregroundStyle(Fx.Color.sea)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Fx.Color.paper)
            }
        }
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: Fx.Radius.s))
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
                            field(String(localized: "Case number"), value: item.caseNumber ?? String(localized: "Not given by the e-service"))
                            field(String(localized: "Place"), value: item.locationText.isEmpty ? "–" : item.locationText)
                            if let lat = item.latitude, let lng = item.longitude {
                                let center = CLLocationCoordinate2D(latitude: lat, longitude: lng)
                                Map(initialPosition: .region(MKCoordinateRegion(
                                    center: center,
                                    latitudinalMeters: 400,
                                    longitudinalMeters: 400
                                )), interactionModes: []) {
                                    Marker(item.locationText, coordinate: center)
                                        .tint(Fx.Color.accent)
                                }
                                .frame(height: 140)
                                .clipShape(RoundedRectangle(cornerRadius: Fx.Radius.s))
                                .allowsHitTesting(false)
                                .accessibilityHidden(true)
                            }
                            field(String(localized: "Description"), value: item.description)
                            if item.thumbnail != nil {
                                HistoryThumbnail(item: item, spec: spec, side: 120)
                            }
                        }
                    }
                    .padding(Fx.Space.l)
                }
            } else {
                ContentUnavailableView("Report not found", systemImage: "questionmark.folder")
            }
        }
        .fxScreenBackground()
        .navigationBarTitleDisplayMode(.inline)
    }

    private func field(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: Fx.Space.xs) {
            Text(title)
                .font(Fx.Font.footnote.weight(.semibold))
                .foregroundStyle(Fx.Color.inkSoft)
            Text(value)
                .font(Fx.Font.body)
                .foregroundStyle(Fx.Color.ink)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}
