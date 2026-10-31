import Foundation
import SwiftUI

/// In-app display preferences, saved in UserDefaults `fixa.display` and applied at the root.
/// Every value starts at "follow the iPhone". "Delete all my data from this phone" keeps them.
struct DisplaySettings: Codable, Equatable, Sendable {
    enum Appearance: String, Codable, CaseIterable, Sendable {
        case automatic, light, dark
    }

    /// `nil` follows the iPhone's text size.
    var textSize: TextSizeStep?
    var appearance: Appearance = .automatic
    var higherContrast = false
    var boldText = false
    var reduceMotion = false
    var vibration = true

    static let key = "fixa.display"

    init() {}

    /// Missing or unknown values fall back to their defaults, so an older save never resets everything.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        textSize = try? container.decodeIfPresent(TextSizeStep.self, forKey: .textSize)
        appearance = (try? container.decodeIfPresent(Appearance.self, forKey: .appearance)) ?? .automatic
        higherContrast = (try? container.decodeIfPresent(Bool.self, forKey: .higherContrast)) ?? false
        boldText = (try? container.decodeIfPresent(Bool.self, forKey: .boldText)) ?? false
        reduceMotion = (try? container.decodeIfPresent(Bool.self, forKey: .reduceMotion)) ?? false
        vibration = (try? container.decodeIfPresent(Bool.self, forKey: .vibration)) ?? true
    }

    static func load() -> DisplaySettings {
        guard let data = UserDefaults.standard.data(forKey: key),
              let settings = try? JSONDecoder().decode(DisplaySettings.self, from: data) else { return DisplaySettings() }
        return settings
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }
}

/// The 8 text sizes offered in Settings, capped at AX3 (the largest size the screens are laid out for).
enum TextSizeStep: String, Codable, CaseIterable, Sendable {
    case medium, large, xLarge, xxLarge, xxxLarge, accessibility1, accessibility2, accessibility3

    var dynamicTypeSize: DynamicTypeSize {
        switch self {
        case .medium: .medium
        case .large: .large
        case .xLarge: .xLarge
        case .xxLarge: .xxLarge
        case .xxxLarge: .xxxLarge
        case .accessibility1: .accessibility1
        case .accessibility2: .accessibility2
        case .accessibility3: .accessibility3
        }
    }

    /// The closest step to a system size: smaller sizes become `medium`, larger ones `accessibility3`.
    init(nearest size: DynamicTypeSize) {
        switch size {
        case .xSmall, .small, .medium: self = .medium
        case .large: self = .large
        case .xLarge: self = .xLarge
        case .xxLarge: self = .xxLarge
        case .xxxLarge: self = .xxxLarge
        case .accessibility1: self = .accessibility1
        case .accessibility2: self = .accessibility2
        default: self = .accessibility3
        }
    }

    /// 1-based position, for "Size 4 of 8".
    var number: Int { (Self.allCases.firstIndex(of: self) ?? 0) + 1 }

    var smaller: TextSizeStep? {
        guard let index = Self.allCases.firstIndex(of: self), index > 0 else { return nil }
        return Self.allCases[index - 1]
    }

    var larger: TextSizeStep? {
        guard let index = Self.allCases.firstIndex(of: self), index + 1 < Self.allCases.count else { return nil }
        return Self.allCases[index + 1]
    }
}

/// The app's UI languages, in picker order: English and Swedish first, then by native name
/// (Latin, Greek, Cyrillic, Arabic script). `nil` in `AppModel.language` means "Same as iPhone".
/// `pt` ships European Portuguese text.
enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case en, sv, cs, da, de, et, es, fr, it, lv, lt, hu, nl, nb, pl, pt, ro, fi, el, ru, uk, ar

    var id: String { rawValue }

    var locale: Locale { Locale(identifier: rawValue) }

    /// The language's name in its own script ("Svenska", "العربية").
    var nativeName: String {
        name(in: locale)
    }

    /// The language's name as written in `locale`.
    func name(in locale: Locale) -> String {
        let name = locale.localizedString(forLanguageCode: rawValue) ?? rawValue
        return name.capitalized(with: locale)
    }

    /// The first of the iPhone's preferred languages that Fixa ships, else English. Reads the
    /// iPhone-wide list, not this app's `AppleLanguages` that the Language page writes.
    nonisolated static var system: AppLanguage {
        let device = UserDefaults.standard.persistentDomain(forName: UserDefaults.globalDomain)?["AppleLanguages"] as? [String]
        for identifier in device ?? Locale.preferredLanguages {
            if let code = Locale(identifier: identifier).language.languageCode?.identifier,
               let language = AppLanguage(rawValue: code) {
                return language
            }
        }
        return .en
    }

    static let storageKey = "fixa.language"
}
