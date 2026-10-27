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
                                HistoryRow(item: item, spec: spec, isSending: model.sendingIDs.contains(item.id))
                            }
                            .listRowBackground(Fx.Color.card)
                        }
                        .onDelete { offsets in
                            let ids = Set(offsets.map { model.history.items[$0].id })
                            model.removeReports(ids)
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
    var isSending = false
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
                if item.status != .sent || isSending {
                    HistoryStatusLabel(status: item.status, isSending: isSending)
                }
            }
        }
        .padding(.vertical, Fx.Space.xs)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("history.row")
    }
}

/// How far a report got, for anything not confirmed by the e-service. Icon plus words, never colour alone.
private struct HistoryStatusLabel: View {
    let status: HistoryItem.Status
    var isSending = false

    var body: some View {
        Label {
            Text(title)
        } icon: {
            Image(systemName: symbol)
        }
        .font(Fx.Font.footnote.weight(.semibold))
        .foregroundStyle(Fx.Color.ink)
    }

    private var title: String {
        if isSending {
            return String(localized: "Sending…", bundle: L10n.bundle, locale: L10n.locale)
        }
        switch status {
        case .sent: return String(localized: "Sent", bundle: L10n.bundle, locale: L10n.locale)
        case .waiting: return String(localized: "Waiting to send", bundle: L10n.bundle, locale: L10n.locale)
        case .maybeSent: return String(localized: "May have been sent", bundle: L10n.bundle, locale: L10n.locale)
        case .notSent: return String(localized: "Not sent yet", bundle: L10n.bundle, locale: L10n.locale)
        }
    }

    private var symbol: String {
        if isSending { return "paperplane" }
        switch status {
        case .sent: return "checkmark.circle"
        case .waiting: return "clock.arrow.circlepath"
        case .maybeSent: return "questionmark.circle"
        case .notSent: return "exclamationmark.circle"
        }
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
    @State private var isSendAgainConfirmPresented = false

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
                        if item.status != .sent {
                            statusCard(item)
                        }
                        FxCard {
                            if let caseNumber = item.caseNumber {
                                VStack(alignment: .leading, spacing: Fx.Space.s) {
                                    field(String(localized: "Case number", bundle: L10n.bundle, locale: L10n.locale), value: caseNumber)
                                    FxCopyButton(title: String(localized: "Copy case number", bundle: L10n.bundle, locale: L10n.locale), value: caseNumber)
                                }
                            } else if item.status == .sent {
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
            if item?.status == .waiting || item?.status == .notSent {
                Text("Fixa won't send it, and it disappears from Sent reports.")
            } else {
                Text("It disappears from Sent reports in Fixa. The report itself stays with \(spec.municipality.name).")
            }
        }
        .confirmationDialog(
            Text("Send this report again?"),
            isPresented: $isSendAgainConfirmPresented,
            titleVisibility: .visible
        ) {
            Button {
                Task { await model.sendNow(itemID) }
            } label: {
                Text("Send again anyway")
            }
        } message: {
            Text("If the first one arrived, \(spec.municipality.name) gets the same report twice.")
        }
    }

    /// Where an unconfirmed report stands and what the user can do about it.
    private func statusCard(_ item: HistoryItem) -> some View {
        let isSending = model.sendingIDs.contains(item.id)
        let text = model.reportText(for: item.id)
        return VStack(alignment: .leading, spacing: Fx.Space.m) {
            switch item.status {
            case .sent:
                EmptyView()
            case .waiting:
                FxBanner(
                    kind: .info,
                    title: String(localized: "Waiting to send", bundle: L10n.bundle, locale: L10n.locale),
                    message: model.isOnline
                        ? String(localized: "Your report is saved on this phone. Fixa tries again in a little while.", bundle: L10n.bundle, locale: L10n.locale)
                        : String(localized: "Your report is saved on this phone. Fixa sends it when you're back online.", bundle: L10n.bundle, locale: L10n.locale)
                )
            case .maybeSent:
                FxBanner(
                    kind: .warning,
                    title: String(localized: "May have been sent", bundle: L10n.bundle, locale: L10n.locale),
                    message: model.wantsReply(item.id)
                        ? String(localized: "Fixa didn't see a confirmation, but it may well have arrived. Check your e-mail for a confirmation before you send it again.", bundle: L10n.bundle, locale: L10n.locale)
                        : String(localized: "Fixa didn't see a confirmation, but it may well have arrived. Sending it again may create a second case.", bundle: L10n.bundle, locale: L10n.locale)
                )
                if let text {
                    FxCopyButton(title: String(localized: "Copy report text", bundle: L10n.bundle, locale: L10n.locale), value: text)
                    FxSecondaryButton(title: String(localized: "Send again anyway", bundle: L10n.bundle, locale: L10n.locale), systemImage: "arrow.clockwise") {
                        isSendAgainConfirmPresented = true
                    }
                    .disabled(isSending)
                }
            case .notSent:
                FxBanner(
                    kind: .warning,
                    title: String(localized: "Not sent yet", bundle: L10n.bundle, locale: L10n.locale),
                    message: String(localized: "Fixa tried a few times and couldn't get it through. Try again now, or copy the text and e-mail it.", bundle: L10n.bundle, locale: L10n.locale)
                )
                if text != nil {
                    FxPrimaryButton(
                        title: String(localized: "Try again now", bundle: L10n.bundle, locale: L10n.locale),
                        systemImage: "arrow.clockwise",
                        isLoading: isSending
                    ) {
                        Task { await model.sendNow(item.id) }
                    }
                    .disabled(isSending)
                }
                if let text {
                    FxCopyButton(title: String(localized: "Copy report text", bundle: L10n.bundle, locale: L10n.locale), value: text)
                }
            }
        }
    }

    private func title(for item: HistoryItem) -> String {
        spec.tile(id: item.tileID)?.title.resolve(L10n.locale) ?? String(localized: "Report", bundle: L10n.bundle, locale: L10n.locale)
    }

    private func remove() {
        model.removeReports([itemID])
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
