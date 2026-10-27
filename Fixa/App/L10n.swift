import Foundation
import ObjectiveC
import UIKit

/// The app's UI language, switchable at runtime without a restart.
///
/// `String(localized:)` ignores any `Bundle.main` override (it resolves the language itself), so every
/// call passes `bundle: L10n.bundle, locale: L10n.locale`; `scripts/check-strings.py` enforces it.
/// `Bundle.main` is also swapped to `L10nBundle` so lookups through `Bundle.localizedString`
/// (SwiftUI `Text("literal")`, `Label`, `Button`, navigation titles) read the chosen `.lproj`.
/// `RootView` sets `\.locale`, `\.layoutDirection` and `.id(effectiveLanguage)` so the tree redraws.
nonisolated enum L10n {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var chosen: AppLanguage?
    nonisolated(unsafe) private static var lproj: Bundle?

    /// The in-app choice; `nil` is "Same as iPhone".
    static var language: AppLanguage? { lock.withLock { chosen } }

    /// The language the UI shows now.
    static var effectiveLanguage: AppLanguage { language ?? .system }

    /// The UI language with the iPhone's region (`ar_SE`), so dates keep the local order.
    static var locale: Locale {
        let code = effectiveLanguage.rawValue
        guard let region = Locale.current.region?.identifier else { return Locale(identifier: code) }
        return Locale(identifier: "\(code)_\(region)")
    }

    /// The chosen language's `.lproj` bundle (the main bundle if it is missing).
    static var bundle: Bundle { lock.withLock { lproj } ?? .main }

    static var isRTL: Bool {
        Locale.Language(identifier: effectiveLanguage.rawValue).characterDirection == .rightToLeft
    }

    /// Switches the UI language. `savesSystemSetting` also writes `AppleLanguages`, the value iOS
    /// shows in Settings › Fixa › Language and uses for system sheets from the next launch.
    @MainActor
    static func apply(_ language: AppLanguage?, savesSystemSetting: Bool) {
        installBundleOverride()
        let code = (language ?? .system).rawValue
        let url = Bundle.main.bundleURL.appendingPathComponent("\(code).lproj", isDirectory: true)
        let bundle = Bundle(url: url)
        lock.withLock {
            chosen = language
            lproj = bundle
        }
        if savesSystemSetting {
            if let language {
                UserDefaults.standard.set([language.rawValue], forKey: "AppleLanguages")
            } else {
                UserDefaults.standard.removeObject(forKey: "AppleLanguages")
            }
        }
        UIApplication.shared.accessibilityLanguage = code
        // UIKit parts (navigation bar, back swipe, push direction) read this when they are rebuilt.
        let attribute: UISemanticContentAttribute = isRTL ? .forceRightToLeft : .forceLeftToRight
        UIView.appearance().semanticContentAttribute = attribute
        UINavigationBar.appearance().semanticContentAttribute = attribute
        for scene in UIApplication.shared.connectedScenes {
            for window in (scene as? UIWindowScene)?.windows ?? [] {
                window.semanticContentAttribute = attribute
            }
        }
    }

    @MainActor private static var isInstalled = false

    @MainActor
    private static func installBundleOverride() {
        guard !isInstalled else { return }
        isInstalled = true
        object_setClass(Bundle.main, L10nBundle.self)
    }
}

/// `Bundle.main`'s class after `L10n.apply`: string lookups go to the chosen `.lproj`.
private nonisolated final class L10nBundle: Bundle, @unchecked Sendable {
    override func localizedString(forKey key: String, value: String?, table tableName: String?) -> String {
        if let bundle = L10n.lprojIfChosen {
            return bundle.localizedString(forKey: key, value: value, table: tableName)
        }
        return super.localizedString(forKey: key, value: value, table: tableName)
    }
}

private nonisolated extension L10n {
    /// The `.lproj` to read from; nil before `apply` ran.
    static var lprojIfChosen: Bundle? { lock.withLock { lproj } }
}
