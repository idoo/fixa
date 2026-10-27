import FixaKit
import SwiftUI

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

    var body: some View {
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
        case .profile: ProfileScreen()
        }
    }
}
