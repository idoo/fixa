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
                // Words come from the app by state, never from the downloaded status file.
                if model.sendsPause(for: nil) != nil || model.adapterStatus(for: nil).state == .down {
                    FxBanner(
                        kind: .warning,
                        title: String(localized: "Fixa can't send to \(spec.municipality.name) right now", bundle: L10n.bundle, locale: L10n.locale),
                        message: String(localized: "Your report is saved. You can use the kommun's website.", bundle: L10n.bundle, locale: L10n.locale),
                        actionTitle: String(localized: "Open the kommun's website", bundle: L10n.bundle, locale: L10n.locale),
                        action: openWebsite
                    )
                    .accessibilityIdentifier("home.pausedBanner")
                } else if model.adapterStatus(for: nil).state == .degraded {
                    FxBanner(
                        kind: .warning,
                        title: String(localized: "The municipality's e-service has changed", bundle: L10n.bundle, locale: L10n.locale),
                        message: String(localized: "Fixa is an independent app and is being updated. Your report is saved. You can use the kommun's website.", bundle: L10n.bundle, locale: L10n.locale),
                        actionTitle: String(localized: "Open the kommun's website", bundle: L10n.bundle, locale: L10n.locale),
                        action: openWebsite
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
                    .font(Fx.Font.callout)
                    .foregroundStyle(Fx.Color.ink2)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, Fx.Space.s)
                    .accessibilityAddTraits(.isHeader)

                FxTileGrid(columns: columns, spacing: Fx.Space.m) {
                    ForEach(spec.tiles) { tile in
                        FxTile(
                            title: tile.title.resolve(L10n.locale),
                            systemImage: tile.symbol,
                            categoryID: tile.categoryID,
                            isSelected: model.draft.tileID == tile.id && !model.path.isEmpty
                        ) {
                            model.startReport(tile: tile)
                        }
                        .disabled(!model.canStartForm(adapterID: spec.id))
                        .accessibilityIdentifier("home.tile.\(tile.id)")
                    }
                }

                if !model.services.isEmpty {
                    VStack(alignment: .leading, spacing: Fx.Space.s) {
                        FxGroupHeader(String(localized: "More forms", bundle: L10n.bundle, locale: L10n.locale))
                        ForEach(model.services, id: \.id) { service in
                            if let info = service.service {
                                HomeServiceRow(
                                    title: info.title.resolve(L10n.locale),
                                    subtitle: info.subtitle?.resolve(L10n.locale),
                                    notice: serviceNotice(service.id),
                                    systemImage: info.symbol,
                                    categoryID: service.tiles.first?.categoryID
                                ) {
                                    model.openService(adapterID: service.id)
                                }
                                .disabled(!model.canStartForm(adapterID: service.id))
                                .accessibilityIdentifier("home.service.\(service.id)")
                            }
                        }
                    }
                }

                VStack(spacing: Fx.Space.m) {
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
                .padding(.top, Fx.Space.s)
            }
            .padding(.horizontal, Fx.Space.l)
            .padding(.top, Fx.Space.xs)
            .padding(.bottom, Fx.Space.l)
        }
        .fxScreenBackground()
        .kommunWebLinks(spec: spec)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    model.path.append(.settings)
                } label: {
                    Label("Settings", systemImage: "gearshape")
                        .labelStyle(.iconOnly)
                }
                .accessibilityLabel(Text("Settings"))
                .accessibilityIdentifier("home.settings")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    model.path.append(.history)
                } label: {
                    Label("Sent reports", systemImage: "clock.arrow.circlepath")
                        .labelStyle(.iconOnly)
                }
                .accessibilityLabel(Text("Sent reports"))
                .accessibilityIdentifier("home.history")
            }
        }
    }

    /// The kommun's own web form: with the unsent draft's text copied when there is one, in that
    /// draft's own form.
    private func openWebsite() {
        if model.draftHasContent {
            model.openWebForm(model.webFallbackText(for: model.draft), adapterID: model.draft.adapterID)
        } else {
            KommunWeb.open(spec.webFormURL, spec: spec)
        }
    }

    /// A "More forms" row's own state: waiting for the report being sent, paused or down, or changed.
    private func serviceNotice(_ adapterID: String) -> String? {
        if !model.canStartForm(adapterID: adapterID) {
            return String(localized: "Wait until the report is sent", bundle: L10n.bundle, locale: L10n.locale)
        }
        let state = model.adapterStatus(for: adapterID).state
        if model.sendsPause(for: adapterID) != nil || state == .down {
            return String(localized: "Fixa can't send right now", bundle: L10n.bundle, locale: L10n.locale)
        }
        if state == .degraded {
            return String(localized: "The municipality's e-service has changed", bundle: L10n.bundle, locale: L10n.locale)
        }
        return nil
    }

    /// "Värmdö" from "Värmdö kommun": the subtitle stays descriptive.
    private var placeName: String {
        let name = spec.municipality.name
        for suffix in [" kommun", " Municipality"] where name.hasSuffix(suffix) {
            return String(name.dropLast(suffix.count))
        }
        return name
    }

    /// Time-aware urgent line under the tiles; the number appears once, in the detail line. Only acute
    /// water and sewer faults are a call; "Other questions?" under it opens the kommun's contact page.
    private func urgentRow(_ emergency: AdapterSpec.Emergency) -> some View {
        let contact = EmergencyRouter.contact(for: .now, emergency: emergency)
        let digits = contact.phone.filter(\.isNumber)
        // Number first and unbreakable (NBSP, non-breaking hyphen): if the line wraps, only the name moves.
        let number = contact.phone.replacingOccurrences(of: " ", with: "\u{00A0}").replacingOccurrences(of: "-", with: "\u{2011}")
        return VStack(alignment: .leading, spacing: Fx.Space.xs) {
            FxCallRow(
                title: String(localized: "No water or a blocked sewer?", bundle: L10n.bundle, locale: L10n.locale),
                detail: "\(number.ltrIsolated) · \(contact.title.resolve(L10n.locale))",
                accessibilityValue: "\(contact.phone), \(contact.title.resolve(L10n.locale))"
            ) {
                if let url = URL(string: "tel:\(digits)") {
                    openURL(url)
                }
            }
            if let page = spec.contact?.pageURL ?? emergency.infoURL {
                OtherQuestionsLink(url: page, text: String(localized: "Other questions? Ask the kommun", bundle: L10n.bundle, locale: L10n.locale))
                    .padding(.horizontal, Fx.Space.xs)
            }
        }
    }
}

/// One "More forms" row on Home: the e-service's glyph, title and what it is for, on a card. Opens that
/// form. Selection haptic like the tiles; at least 44 pt tall, grows with Dynamic Type. `notice` is the
/// form's own state (paused, down, waiting for a send) on a line of its own.
private struct HomeServiceRow: View {
    let title: String
    let subtitle: String?
    let notice: String?
    let systemImage: String
    let categoryID: String?
    let action: () -> Void

    @State private var taps = 0
    @Environment(\.fxHaptics) private var haptics
    @ScaledMetric(relativeTo: .body) private var iconSide: CGFloat = 40

    var body: some View {
        Button {
            taps += 1
            action()
        } label: {
            HStack(spacing: Fx.Space.m) {
                FxCategoryIcon(systemImage: systemImage, categoryID: categoryID, side: min(iconSide, 72))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(Fx.Font.headline)
                        .foregroundStyle(Fx.Color.ink)
                    if let subtitle {
                        Text(subtitle)
                            .font(Fx.Font.footnote)
                            .foregroundStyle(Fx.Color.ink2)
                    }
                    if let notice {
                        Label(notice, systemImage: "exclamationmark.triangle.fill")
                            .font(Fx.Font.footnote)
                            .foregroundStyle(Fx.Color.ink2)
                    }
                }
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                Image(systemName: "chevron.right")
                    .font(Fx.Font.footnote.weight(.semibold))
                    .foregroundStyle(Fx.Color.ink2)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, Fx.Space.m)
            .padding(.vertical, Fx.Space.s)
            .frame(minHeight: Fx.minTarget + Fx.Space.s)
            .fxCardSurface(RoundedRectangle(cornerRadius: Fx.Radius.m, style: .continuous))
            .contentShape(.rect(cornerRadius: Fx.Radius.m, style: .continuous))
        }
        .buttonStyle(FxPressStyle())
        .sensoryFeedback(.selection, trigger: taps) { _, _ in haptics }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(title))
        .accessibilityValue(Text([subtitle, notice].compactMap { $0 }.joined(separator: ", ")))
        .accessibilityHint(Text(String(localized: "Opens the form", bundle: L10n.bundle, locale: L10n.locale)))
        .accessibilityAddTraits(.isButton)
    }
}

/// A kommun page under an emergency call card ("Other questions?"), opened in the in-app Safari view
/// when the screen applies `kommunWebLinks(spec:)`.
struct OtherQuestionsLink: View {
    let url: URL
    let text: String

    var body: some View {
        FxIconRow(systemImage: "safari", text: text, link: url)
            .accessibilityHint(Text("Opens in Safari"))
            .accessibilityIdentifier("emergency.otherQuestions")
    }
}
