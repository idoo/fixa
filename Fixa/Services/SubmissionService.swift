import Foundation
import FixaKit
import Observation

/// What the receipt screen shows. Dry runs never reach the municipality.
struct SentReport: Equatable, Sendable {
    var caseNumber: String?
    var date: Date
    var isDryRun: Bool
}

/// Wraps `AbouSubmitter` and publishes progress for the Review screen.
@Observable
@MainActor
final class SubmissionService {
    enum Phase: Equatable {
        case idle
        case sending(SubmissionStage)
        case failed(SubmissionError)
    }

    private(set) var phase: Phase = .idle

    var isSending: Bool {
        if case .sending = phase { return true }
        return false
    }

    var error: SubmissionError? {
        if case .failed(let error) = phase { return error }
        return nil
    }

    func reset() {
        phase = .idle
    }

    /// Returns nil when sending failed; `phase` then holds the error.
    func submit(_ draft: ReportDraft, spec: AdapterSpec, dryRun: Bool, recordResponses: Bool = false) async -> SentReport? {
        guard !isSending else { return nil }
        phase = .sending(.starting)
        let submitter = recordResponses
            ? AbouSubmitter(spec: spec, transport: RecordingTransport())
            : AbouSubmitter(spec: spec)
        do {
            let receipt = try await submitter.submit(draft, dryRun: dryRun) { stage in
                Task { @MainActor [weak self] in
                    guard let self, self.isSending else { return }
                    self.phase = .sending(stage)
                }
            }
            phase = .idle
            return SentReport(
                caseNumber: receipt?.caseNumber,
                date: receipt?.submittedAt ?? .now,
                isDryRun: dryRun
            )
        } catch let error as SubmissionError {
            phase = .failed(error)
        } catch is CancellationError {
            phase = .idle
        } catch {
            phase = .failed(.transport(error.localizedDescription))
        }
        return nil
    }
}

extension SubmissionStage {
    /// 1-based step for `FxProgressSteps`.
    var stepIndex: Int {
        switch self {
        case .starting: 1
        case .uploadingPhoto: 2
        case .sendingReport: 3
        case .sendingContact: 4
        case .confirming: 5
        case .done: 5
        }
    }

    static let stepCount = 5

    var label: String {
        switch self {
        case .starting: String(localized: "Opening the e-service…", bundle: L10n.bundle, locale: L10n.locale)
        case .uploadingPhoto: String(localized: "Uploading the photo…", bundle: L10n.bundle, locale: L10n.locale)
        case .sendingReport: String(localized: "Sending the report…", bundle: L10n.bundle, locale: L10n.locale)
        case .sendingContact: String(localized: "Adding your contact details…", bundle: L10n.bundle, locale: L10n.locale)
        case .confirming: String(localized: "Confirming…", bundle: L10n.bundle, locale: L10n.locale)
        case .done: String(localized: "Sent", bundle: L10n.bundle, locale: L10n.locale)
        }
    }
}

extension SubmissionError {
    var userMessage: String {
        switch self {
        case .sessionLocked:
            String(localized: "The e-service is busy with another report from this phone. Wait a minute and try again.", bundle: L10n.bundle, locale: L10n.locale)
        case .serverValidation(let messages):
            messages.isEmpty
                ? String(localized: "The e-service didn't accept the report.", bundle: L10n.bundle, locale: L10n.locale)
                : String(localized: "The e-service says: \(messages.joined(separator: " "))", bundle: L10n.bundle, locale: L10n.locale)
        case .formChanged:
            String(localized: "The municipality seems to have changed its form", bundle: L10n.bundle, locale: L10n.locale)
        case .uploadFailed:
            String(localized: "The photo couldn't be uploaded.", bundle: L10n.bundle, locale: L10n.locale)
        case .http(let code):
            String(localized: "The e-service returned an error (\(code)).", bundle: L10n.bundle, locale: L10n.locale)
        case .transport:
            String(localized: "Couldn't reach the e-service. Check your connection.", bundle: L10n.bundle, locale: L10n.locale)
        case .invalidSpec:
            String(localized: "Fixa's settings for this municipality are broken. Please update the app.", bundle: L10n.bundle, locale: L10n.locale)
        }
    }
}

extension AdapterSpec {
    /// The municipality's own e-service form: the intro page of the channel.
    var eServiceURL: URL? {
        guard let base = URL(string: channel.baseURL) else { return nil }
        return URL(string: channel.introPath, relativeTo: base)?.absoluteURL
    }
}

extension FormDrift {
    /// A prefilled GitHub issue so the owner can update the adapter. Technical facts only:
    /// never the description, place, photo or contact details.
    func issueURL(spec: AdapterSpec) -> URL? {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        var lines = [
            "App: Fixa \(version) (\(build))",
            "Adapter: \(spec.id), spec version \(spec.specVersion)",
            "Page: \(pageID ?? "unknown")",
        ]
        lines.append(missing.isEmpty ? "Missing: none listed" : "Missing: \(missing.joined(separator: ", "))")
        var components = URLComponents(string: "https://github.com/idoo/fixa/issues/new")
        components?.queryItems = [
            URLQueryItem(name: "title", value: "Form changed: \(spec.id) page \(pageID ?? "unknown")"),
            URLQueryItem(name: "body", value: lines.joined(separator: "\n")),
        ]
        return components?.url
    }
}
