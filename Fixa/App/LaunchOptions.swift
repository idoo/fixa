import FixaKit
import Foundation

/// Launch hooks for screenshots and testing. Harmless in Release.
///   -FixaScreen home|report|location|review|receipt|history|about|settings|textsize|language|contact|privacy|onboarding
///                   (onboarding shows the first-launch disclaimer; every other screen, and -FixaDemo, skips it)
///   -FixaStatus degraded|down  forces the municipality e-service status Home shows (status banner)
///   -FixaStatus offline|uncertain  with -FixaDemo 1: the demo report as "Waiting to send" (offline)
///                   or "May have been sent" (uncertain) on the receipt, in Sent reports and on Home
///   -FixaTextSize medium|large|xLarge|xxLarge|xxxLarge|accessibility1|accessibility2|accessibility3
///                   overrides the saved text size for this launch (saved only by a real change in Settings)
///   -FixaLanguage en|sv|fi|ar|uk|pl|system  switches the UI language in-app right after launch,
///                   through the same path as the Language page (saved only outside -FixaDemo)
///   -FixaDemo 1     seeds a demo draft, profile, history and receipt; no network, nothing saved
///   -FixaEmptyHistory 1  with -FixaDemo: leaves the demo history empty (History empty state)
///   -FixaDryRun 1   Review's Send stops at the Summary page (nothing is submitted)
///   -FixaShortcut <tileID>|sent  (Debug only, read in `FixaApp`) applies a quick action / App Shortcut
///                   route at launch: a new report for the tile (an unsent draft wins) or Sent reports
struct LaunchOptions: Sendable {
    enum Screen: String, CaseIterable, Sendable {
        case home, report, location, review, receipt, history, about, settings, textsize, language, contact, privacy, onboarding
    }

    /// `-FixaStatus offline|uncertain`: a send outcome to show without sending anything.
    enum SendState: String, Sendable {
        case offline, uncertain
    }

    var screen: Screen?
    var textSize: TextSizeStep?
    /// `-FixaLanguage`: `.some(nil)` is "Same as iPhone"; nil leaves the saved choice.
    var language: AppLanguage??
    /// `-FixaStatus`: a forced e-service status, or nil to use the real one.
    var status: AdapterStatus?
    var sendState: SendState?
    var demo: Bool
    var emptyHistory: Bool
    var dryRun: Bool
    /// `-FixaTile <id>`: the demo report's tile, for screenshots of tile-specific screens.
    var tile: String?

    static let current = LaunchOptions(arguments: ProcessInfo.processInfo.arguments)

    init(arguments: [String]) {
        func value(_ flag: String) -> String? {
            guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else { return nil }
            return arguments[index + 1]
        }
        func isOn(_ flag: String) -> Bool {
            guard let raw = value(flag)?.lowercased() else { return false }
            return ["1", "yes", "true"].contains(raw)
        }
        screen = value("-FixaScreen").flatMap { Screen(rawValue: $0.lowercased()) }
        textSize = value("-FixaTextSize").flatMap { raw in
            TextSizeStep.allCases.first { $0.rawValue.lowercased() == raw.lowercased() }
        }
        language = value("-FixaLanguage").flatMap { raw -> AppLanguage?? in
            let code = raw.lowercased()
            if code == "system" { return .some(nil) }
            return AppLanguage(rawValue: code).map { .some($0) }
        }
        status = value("-FixaStatus")
            .flatMap { AdapterStatus.State(rawValue: $0.lowercased()) }
            .map { AdapterStatus(state: $0) }
        sendState = value("-FixaStatus").flatMap { SendState(rawValue: $0.lowercased()) }
        demo = isOn("-FixaDemo")
        emptyHistory = isOn("-FixaEmptyHistory")
        dryRun = isOn("-FixaDryRun")
        tile = value("-FixaTile")
    }
}
