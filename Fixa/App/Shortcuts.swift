import AppIntents
import FixaKit
import SwiftUI
import UIKit

// MARK: Home Screen quick actions

/// Gives the window scene `QuickActionSceneDelegate`, so quick actions reach Fixa on a cold launch
/// (`connectionOptions.shortcutItem`) and while it runs (`performActionFor`).
final class FixaAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        configuration.delegateClass = QuickActionSceneDelegate.self
        return configuration
    }
}

final class QuickActionSceneDelegate: NSObject, UIWindowSceneDelegate {
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        if let item = connectionOptions.shortcutItem, let route = ShortcutRoute(item) {
            ShortcutInbox.shared.deliver(route)
        }
    }

    func windowScene(
        _ windowScene: UIWindowScene,
        performActionFor shortcutItem: UIApplicationShortcutItem,
        completionHandler: @escaping (Bool) -> Void
    ) {
        guard let route = ShortcutRoute(shortcutItem) else {
            completionHandler(false)
            return
        }
        ShortcutInbox.shared.deliver(route)
        completionHandler(true)
    }
}

// MARK: App Intents (Siri, Spotlight, Shortcuts)

/// A Home tile of the bundled adapter, titled in the app's language.
nonisolated struct ReportTileEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Problem type"
    static let defaultQuery = ReportTileQuery()

    let id: String
    let title: String
    let symbol: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title)", image: .init(systemName: symbol))
    }

    /// The tiles in adapter order. The app's language: the in-app choice, else the iPhone's.
    @MainActor
    static func all() -> [ReportTileEntity] {
        let catalog = AdapterCatalog.bundled()
        guard let spec = catalog.first(where: { $0.id == AppModel.adapterID }) ?? catalog.first else { return [] }
        let code = UserDefaults.standard.string(forKey: AppLanguage.storageKey) ?? AppLanguage.system.rawValue
        let locale = Locale(identifier: code)
        return spec.tiles.map { ReportTileEntity(id: $0.id, title: $0.title.resolve(locale), symbol: $0.symbol) }
    }
}

nonisolated struct ReportTileQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [ReportTileEntity] {
        await MainActor.run { ReportTileEntity.all() }.filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async throws -> [ReportTileEntity] {
        await MainActor.run { ReportTileEntity.all() }
    }
}

struct StartReportIntent: AppIntent {
    static let title: LocalizedStringResource = "Start a report"
    static let description = IntentDescription("Opens Fixa on a new report. An unsent report you started opens instead.")
    static let supportedModes: IntentModes = .foreground

    @Parameter(title: "Problem type")
    var tile: ReportTileEntity?

    static var parameterSummary: some ParameterSummary {
        Summary("Report \(\.$tile)")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        ShortcutInbox.shared.deliver(.report(tileID: tile?.id))
        return .result()
    }
}

nonisolated struct OpenSentReportsIntent: AppIntent {
    static let title: LocalizedStringResource = "Open sent reports"
    static let description = IntentDescription("Shows the reports you sent with Fixa and their case numbers.")
    static let supportedModes: IntentModes = .foreground

    func perform() async throws -> some IntentResult {
        await MainActor.run { ShortcutInbox.shared.deliver(.sentReports) }
        return .result()
    }
}

/// Phrases are translated in `AppShortcuts.xcstrings`.
nonisolated struct FixaShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartReportIntent(),
            phrases: [
                "Report a problem in \(.applicationName)",
                "Report \(\.$tile) in \(.applicationName)",
                "Start a report in \(.applicationName)",
            ],
            shortTitle: "Report a problem",
            systemImageName: "exclamationmark.bubble"
        )
        AppShortcut(
            intent: OpenSentReportsIntent(),
            phrases: [
                "Show my sent reports in \(.applicationName)",
                "Open sent reports in \(.applicationName)",
            ],
            shortTitle: "Sent reports",
            systemImageName: "clock.arrow.circlepath"
        )
    }
}
