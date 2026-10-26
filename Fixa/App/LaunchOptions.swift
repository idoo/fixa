import Foundation

/// Launch hooks for screenshots and testing. Harmless in Release.
///   -FixaScreen home|report|location|review|receipt|history|about
///   -FixaDemo 1     seeds a demo draft, history and receipt; no network
///   -FixaDryRun 1   Review's Send stops at the Summary page (nothing is submitted)
///   -FixaLiveTest 1 DEBUG builds only (always off in Release): seeds a marked TEST report
///                   (test@test.se, no personal data) on Review and records every server
///                   response to Caches/fixa-responses. Sending is REAL.
struct LaunchOptions: Sendable {
    enum Screen: String, CaseIterable, Sendable {
        case home, report, location, review, receipt, history, about
    }

    var screen: Screen?
    var demo: Bool
    var dryRun: Bool
    var liveTest: Bool

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
        demo = isOn("-FixaDemo")
        dryRun = isOn("-FixaDryRun")
        #if DEBUG
        liveTest = isOn("-FixaLiveTest")
        #else
        liveTest = false
        #endif
    }
}
