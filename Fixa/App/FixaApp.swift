import FixaKit
import SwiftUI
import UIKit

@main
struct FixaApp: App {
    @State private var model: AppModel

    init() {
        let model = AppModel()
        _model = State(initialValue: model)
        // Before launch finishes, as BGTaskScheduler requires.
        BackgroundOutbox.register(model)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
        }
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion

    var body: some View {
        let display = model.display
        let language = model.effectiveLanguage
        content
            // In-app language: locale for Text/formatting, direction for Arabic, and a full redraw
            // so plain Strings built with String(localized:) pick up the new .lproj too.
            .environment(\.locale, L10n.locale)
            .environment(\.layoutDirection, L10n.isRTL ? .rightToLeft : .leftToRight)
            .id(language)
            // `-FixaLanguage`: switches in-app after the first frame, like a tap on the Language page.
            .task {
                if let forced = model.options.language {
                    model.language = forced
                }
            }
            // In-app display settings; each one leaves the iPhone's setting alone unless chosen.
            .transformEnvironment(\.dynamicTypeSize) { size in
                if let step = display.textSize {
                    size = step.dynamicTypeSize
                }
            }
            .transformEnvironment(\.legibilityWeight) { weight in
                if display.boldText {
                    weight = .bold
                }
            }
            .environment(\.fxReduceMotion, systemReduceMotion || display.reduceMotion)
            .environment(\.fxHaptics, display.vibration)
            // Appearance and contrast go on the window so sheets, alerts and the camera follow too.
            .background {
                WindowTraitBridge(appearance: display.appearance, higherContrast: display.higherContrast)
                    .frame(width: 0, height: 0)
                    .accessibilityHidden(true)
            }
    }

    @ViewBuilder
    private var content: some View {
        @Bindable var model = model
        if let spec = model.spec {
            NavigationStack(path: $model.path) {
                HomeScreen(spec: spec)
                    .navigationDestination(for: Route.self) { route in
                        destination(route, spec: spec)
                    }
            }
            .tint(Fx.Color.sea)
            .sheet(isPresented: $model.isLocationPickerPresented) {
                LocationPickerSheet(spec: spec)
            }
            // First-launch disclaimer; a cover so it reads as one calm page, not a dismissable card.
            .fullScreenCover(isPresented: $model.isOnboardingPresented) {
                OnboardingScreen()
            }
            .onChange(of: scenePhase) { _, phase in
                if phase != .active {
                    model.persistNow()
                }
                if phase == .background {
                    model.scheduleBackgroundSend()
                }
            }
            // SendGuard: a repeat of a recent report asks first (Cancel is the default); too many
            // reports in a short time blocks. Here so Review's Send stays a plain `model.send()`.
            .alert(
                sendGuardTitle,
                isPresented: Binding(
                    get: { model.sendGuardAlert != nil },
                    set: { if !$0 { model.sendGuardAlert = nil } }
                ),
                presenting: model.sendGuardAlert
            ) { alert in
                switch alert {
                case .duplicate:
                    Button(String(localized: "Cancel", bundle: L10n.bundle, locale: L10n.locale), role: .cancel) {}
                        .keyboardShortcut(.defaultAction)
                    Button(String(localized: "Send anyway", bundle: L10n.bundle, locale: L10n.locale)) {
                        Task { await model.sendAnyway() }
                    }
                case .tooMany:
                    Button(String(localized: "OK", bundle: L10n.bundle, locale: L10n.locale), role: .cancel) {}
                }
            } message: { alert in
                Text(sendGuardMessage(alert))
            }
        } else {
            ContentUnavailableView(
                "Fixa couldn't start",
                systemImage: "exclamationmark.triangle",
                description: Text("The settings for the municipality are missing. Please reinstall the app.")
            )
            .fxScreenBackground()
        }
    }

    private var sendGuardTitle: String {
        switch model.sendGuardAlert {
        case .tooMany?:
            String(localized: "Please wait a while", bundle: L10n.bundle, locale: L10n.locale)
        default:
            String(localized: "Already reported?", bundle: L10n.bundle, locale: L10n.locale)
        }
    }

    private func sendGuardMessage(_ alert: AppModel.SendGuardAlert) -> String {
        switch alert {
        case .duplicate(let previous):
            let formatter = DateComponentsFormatter()
            formatter.unitsStyle = .full
            formatter.maximumUnitCount = 1
            formatter.allowedUnits = [.day, .hour, .minute]
            var calendar = Calendar.current
            calendar.locale = L10n.locale
            formatter.calendar = calendar
            let ago = formatter.string(from: max(60, Date.now.timeIntervalSince(previous))) ?? ""
            return String(localized: "You reported this here \(ago) ago. The kommun already has it. Send another report?", bundle: L10n.bundle, locale: L10n.locale)
        case .tooMany(let retryAfter):
            let sameDay = Calendar.current.isDate(retryAfter, inSameDayAs: .now)
            let time = retryAfter.formatted(
                Date.FormatStyle(date: sameDay ? .omitted : .abbreviated, time: .shortened).locale(L10n.locale)
            )
            return String(localized: "You've sent many reports in a short time. Try again at \(time).", bundle: L10n.bundle, locale: L10n.locale)
        }
    }

    @ViewBuilder
    private func destination(_ route: Route, spec: AdapterSpec) -> some View {
        switch route {
        case .report: ReportScreen(spec: spec)
        case .review: ReviewScreen(spec: spec)
        case .receipt: ReceiptScreen(spec: spec)
        case .history: HistoryScreen(spec: spec)
        case .historyDetail(let id): HistoryDetailScreen(spec: spec, itemID: id)
        case .about: AboutScreen(spec: spec)
        case .settings: SettingsScreen()
        case .contactDetails: ProfileScreen()
        case .language: SettingsLanguageScreen()
        case .textSize: SettingsTextSizeScreen()
        case .privacy: PrivacyScreen(spec: spec)
        }
    }
}

/// Applies Appearance (`overrideUserInterfaceStyle`) and Higher contrast
/// (`traitOverrides.accessibilityContrast`) to the hosting window.
private struct WindowTraitBridge: UIViewRepresentable {
    let appearance: DisplaySettings.Appearance
    let higherContrast: Bool

    func makeUIView(context: Context) -> BridgeView {
        let view = BridgeView()
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ view: BridgeView, context: Context) {
        view.appearance = appearance
        view.higherContrast = higherContrast
        view.apply()
    }

    final class BridgeView: UIView {
        var appearance: DisplaySettings.Appearance = .automatic
        var higherContrast = false

        override func didMoveToWindow() {
            super.didMoveToWindow()
            apply()
        }

        func apply() {
            guard let window else { return }
            let style: UIUserInterfaceStyle = switch appearance {
            case .automatic: .unspecified
            case .light: .light
            case .dark: .dark
            }
            if window.overrideUserInterfaceStyle != style {
                window.overrideUserInterfaceStyle = style
            }
            // Reading an unset trait override (`traitOverrides.accessibilityContrast`
            // before anything set it) raises an NSInternalInconsistencyException on
            // device: build 5 crashed at launch whenever Higher contrast was on.
            // Ask `contains` first; only then compare the stored value.
            if higherContrast {
                let overrides = window.traitOverrides
                if !overrides.contains(UITraitAccessibilityContrast.self) || overrides.accessibilityContrast != .high {
                    window.traitOverrides.accessibilityContrast = .high
                }
            } else if window.traitOverrides.contains(UITraitAccessibilityContrast.self) {
                window.traitOverrides.remove(UITraitAccessibilityContrast.self)
            }
        }
    }
}
