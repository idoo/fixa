import FixaKit
import SwiftUI
import UIKit

/// "Tell the developer": an e-mail to support@jvcr.se that the user sees, can edit, and sends
/// themselves. Technical facts only: app and iOS version, device model, app language, adapter,
/// and the kind of the last error with its form page. Never the name, phone, e-mail, description,
/// photo, place or coordinates, and never the e-service's own messages.
struct DeveloperReport: Equatable, Sendable {
    static let address = "support@jvcr.se"

    var adapterID: String?
    var adapterVersion: Int?
    /// A case name such as `formChanged` or `http 503`; nil when nothing failed.
    var errorKind: String?
    var pageID: String?
    /// Form fields or options Fixa could not fill (adapter keys and labels, not user input).
    var missingFields: [String] = []

    init(spec: AdapterSpec?, error: SubmissionError? = nil) {
        adapterID = spec?.id
        adapterVersion = spec?.specVersion
        guard let error else { return }
        switch error {
        case .sessionLocked: errorKind = "sessionLocked"
        case .serverValidation: errorKind = "serverValidation"
        case .formChanged(let drift):
            errorKind = "formChanged"
            pageID = drift.pageID
            missingFields = drift.missing
        case .uploadFailed: errorKind = "uploadFailed"
        case .http(let code): errorKind = "http \(code)"
        case .unavailable(let status, _): errorKind = "unavailable \(status.map(String.init) ?? "page")"
        case .transport: errorKind = "transport"
        case .invalidSpec: errorKind = "invalidSpec"
        case .uncertain: errorKind = "uncertain"
        }
    }

    /// Fixed Swedish subject, so the developer's inbox can sort it whatever the app language.
    var subject: String { "Fixa: problem i appen" }

    @MainActor
    var body: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        var lines = [
            String(localized: "Tell us what happened. You can change or delete anything below before you send it.", bundle: L10n.bundle, locale: L10n.locale),
            "",
            "",
            "",
            "---",
            "App: Fixa \(version) (\(build))",
            "iOS: \(UIDevice.current.systemVersion)",
            "Device: \(Self.deviceModel)",
            "Language: \(L10n.locale.identifier)",
            "Adapter: \(adapterID ?? "none") v\(adapterVersion.map(String.init) ?? "?")",
        ]
        if let errorKind {
            lines.append("Last error: \(errorKind)")
            lines.append("Page: \(pageID ?? "unknown")")
        }
        if !missingFields.isEmpty {
            lines.append("Missing: \(missingFields.joined(separator: ", "))")
        }
        return lines.joined(separator: "\n")
    }

    @MainActor
    var mailtoURL: URL? {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = Self.address
        components.queryItems = [
            URLQueryItem(name: "subject", value: subject),
            URLQueryItem(name: "body", value: body),
        ]
        return components.url
    }

    /// Hardware identifier such as `iPhone16,2` (the simulator reports the simulated one).
    static var deviceModel: String {
        if let simulated = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] {
            return simulated
        }
        var system = utsname()
        uname(&system)
        return withUnsafeBytes(of: &system.machine) { raw in
            String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
        }
    }
}

extension View {
    /// Set `report` to start "Tell the developer": Mail's composer when Mail is set up, else the
    /// default mail app via `mailto:`, else the address with a copy button. Nothing is sent
    /// unless the user sends it from their mail app. `report` goes back to nil once handled.
    func developerReport(_ report: Binding<DeveloperReport?>) -> some View {
        modifier(DeveloperReportPresenter(request: report))
    }
}

private struct DeveloperReportPresenter: ViewModifier {
    @Binding var request: DeveloperReport?
    @Environment(\.openURL) private var openURL
    @State private var composing: DeveloperReport?
    @State private var isAddressPresented = false

    func body(content: Content) -> some View {
        content
            .onChange(of: request) { _, report in
                guard let report else { return }
                request = nil
                start(report)
            }
            .sheet(item: $composing) { report in
                MailComposer(
                    recipients: [DeveloperReport.address],
                    subject: report.subject,
                    body: report.body,
                    attachment: nil,
                    onFinish: { _ in composing = nil }
                )
                .ignoresSafeArea()
            }
            .alert(Text("Write to the developer"), isPresented: $isAddressPresented) {
                Button {
                    UIPasteboard.general.string = DeveloperReport.address
                } label: {
                    Text("Copy address")
                }
                Button(role: .cancel) {} label: {
                    Text("Done")
                }
            } message: {
                Text("No mail app is set up on this phone. Write to \(DeveloperReport.address.ltrIsolated) from any e-mail.")
            }
    }

    private func start(_ report: DeveloperReport) {
        if MailComposer.canSendMail {
            composing = report
        } else if let url = report.mailtoURL {
            openURL(url) { accepted in
                if !accepted { isAddressPresented = true }
            }
        } else {
            isAddressPresented = true
        }
    }
}

extension DeveloperReport: Identifiable {
    /// One composer at a time; the identity only drives `.sheet(item:)`.
    var id: String { "\(adapterID ?? "")|\(errorKind ?? "")|\(pageID ?? "")" }
}
