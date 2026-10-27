import FixaKit
import SwiftUI
import UIKit

@main
struct FixaApp: App {
    @State private var model = AppModel()

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
        content
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
            // Checks for an updated adapter and the e-service status (at most every 6 hours).
            .task(id: scenePhase) {
                if scenePhase == .active, !model.options.demo {
                    await model.adapters.refresh()
                }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase != .active {
                    model.persistNow()
                }
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
            if higherContrast {
                if window.traitOverrides.accessibilityContrast != .high {
                    window.traitOverrides.accessibilityContrast = .high
                }
            } else if window.traitOverrides.contains(UITraitAccessibilityContrast.self) {
                window.traitOverrides.remove(UITraitAccessibilityContrast.self)
            }
        }
    }
}
