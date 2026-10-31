import FixaKit
import Foundation
import UIKit

/// Where a Home Screen quick action, an App Shortcut (Siri, Spotlight, Shortcuts) or the
/// `-FixaShortcut` launch hook takes the resident. All of them go through `AppModel.open(_:)`.
enum ShortcutRoute: Equatable, Sendable {
    /// A new report about this tile; nil or an unknown tile opens Home.
    case report(tileID: String?)
    case sentReports

    nonisolated static let reportType = "se.jvcr.fixa.report"
    nonisolated static let sentType = "se.jvcr.fixa.sent"
    nonisolated static let tileKey = "tile"

    init?(_ item: UIApplicationShortcutItem) {
        switch item.type {
        case Self.reportType: self = .report(tileID: item.userInfo?[Self.tileKey] as? String)
        case Self.sentType: self = .sentReports
        default: return nil
        }
    }

    /// `-FixaShortcut <tileID|sent>`.
    init(argument: String) {
        self = argument.lowercased() == "sent" ? .sentReports : .report(tileID: argument)
    }
}

/// Hands routes from the scene delegate and App Intents to `RootView`, which applies them to the
/// model. Holds one until the UI is up, so a cold launch from a quick action is not lost.
@Observable
final class ShortcutInbox {
    static let shared = ShortcutInbox()
    private(set) var pending: ShortcutRoute?

    func deliver(_ route: ShortcutRoute) {
        pending = route
    }

    func take() -> ShortcutRoute? {
        defer { pending = nil }
        return pending
    }
}

extension AppModel {
    /// Applies a shortcut. An unsent draft with text or photos always wins: Fixa reopens it (as the
    /// draft restore at launch does) instead of replacing it with a new report. A send under way is
    /// never interrupted. A report already on its receipt is finished first, as Done would.
    func open(_ route: ShortcutRoute) {
        guard !isSendingDraft else { return }
        if sent != nil {
            finish()
        }
        sendGuardAlert = nil
        switch route {
        case .report(let tileID):
            startReport(tileID: tileID)
        case .sentReports:
            showSentReports()
        }
    }

    func startReport(tileID: String?) {
        if draftHasContent {
            // Already on the draft (Report or Review): stay there.
            if path.first != .report {
                isLocationPickerPresented = false
                path = [.report]
            }
            return
        }
        isLocationPickerPresented = false
        if let tile = spec?.tile(id: tileID) {
            startReport(tile: tile)
        } else {
            path = []
        }
    }

    func showSentReports() {
        isLocationPickerPresented = false
        path = [.history]
    }

    /// Home Screen quick actions: the first two tiles in adapter order, the catch-all "other" tile
    /// (or the third), and Sent reports. Titles in the app's current language.
    func refreshQuickActions() {
        guard let spec else {
            UIApplication.shared.shortcutItems = []
            return
        }
        var tiles = Array(spec.tiles.prefix(2))
        if let other = spec.tile(id: "other") ?? spec.tiles.dropFirst(2).first, !tiles.contains(other) {
            tiles.append(other)
        }
        var items = tiles.map { tile in
            UIApplicationShortcutItem(
                type: ShortcutRoute.reportType,
                localizedTitle: tile.title.resolve(L10n.locale),
                localizedSubtitle: nil,
                icon: UIApplicationShortcutIcon(systemImageName: tile.symbol),
                userInfo: [ShortcutRoute.tileKey: tile.id as NSString]
            )
        }
        items.append(UIApplicationShortcutItem(
            type: ShortcutRoute.sentType,
            localizedTitle: String(localized: "Sent reports", bundle: L10n.bundle, locale: L10n.locale),
            localizedSubtitle: nil,
            icon: UIApplicationShortcutIcon(systemImageName: "clock.arrow.circlepath"),
            userInfo: nil
        ))
        UIApplication.shared.shortcutItems = items
    }
}
