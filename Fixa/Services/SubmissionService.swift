import Foundation
import FixaKit
import Observation
import UIKit

/// What the receipt screen shows. Dry runs never reach the municipality.
struct SentReport: Equatable, Sendable {
    enum Outcome: Equatable, Sendable {
        /// The e-service confirmed it.
        case sent
        /// Saved on this phone; Fixa sends it on its own when the e-service can be reached.
        case waiting
        /// The final step went out but no confirmation came back. Never sent again on its own.
        case maybeSent
    }

    var caseNumber: String?
    var date: Date
    var isDryRun: Bool
    var outcome: Outcome = .sent
    /// The Sent reports entry for this report, when there is one.
    var historyID: UUID? = nil
    /// What the e-service's receipt page said, trimmed; nil when it said nothing.
    var kommunMessage: String? = nil
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
    /// Each call gets its own ephemeral URLSession: Abou's cookies live in that session's private
    /// jar only (never `HTTPCookieStorage.shared`) and go away with it. A background task keeps the
    /// send running when the user leaves the app mid-way. `beforeFinalSend` runs right before the
    /// final step goes out and must have persisted that fact when it returns.
    func submit(
        _ draft: ReportDraft,
        spec: AdapterSpec,
        dryRun: Bool,
        beforeFinalSend: @escaping @Sendable () async -> Void = {}
    ) async -> SentReport? {
        guard !isSending else { return nil }
        phase = .sending(.starting)
        let background = BackgroundSend()
        defer { background.end() }
        let session = URLSessionTransport.ephemeral()
        defer { session.session.finishTasksAndInvalidate() }
        let submitter = AbouSubmitter(spec: spec, transport: session)
        do {
            let receipt = try await submitter.submit(draft, dryRun: dryRun, beforeFinalSend: beforeFinalSend) { stage in
                Task { @MainActor [weak self] in
                    guard let self, self.isSending else { return }
                    self.phase = .sending(stage)
                }
            }
            phase = .idle
            let message = receipt?.message.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return SentReport(
                caseNumber: receipt?.caseNumber,
                date: receipt?.submittedAt ?? .now,
                isDryRun: dryRun,
                kommunMessage: message.isEmpty ? nil : message
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

/// Asks iOS for time to finish a send after the app leaves the screen. When that time runs out
/// the task is simply ended: the request is never cancelled from here, so a half-finished final
/// step surfaces as `.uncertain` rather than being retried.
@MainActor
private final class BackgroundSend {
    private var id: UIBackgroundTaskIdentifier = .invalid

    init() {
        id = UIApplication.shared.beginBackgroundTask(withName: "Fixa send report") { @Sendable [weak self] in
            MainActor.assumeIsolated { self?.end() }
        }
    }

    func end() {
        guard id != .invalid else { return }
        UIApplication.shared.endBackgroundTask(id)
        id = .invalid
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
    /// The final step went out but no confirmation came back. Never retry this on its own.
    var isUncertain: Bool {
        if case .uncertain = self { return true }
        return false
    }

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
        case .unavailable:
            String(localized: "The e-service is temporarily unavailable. Fixa will try again later.", bundle: L10n.bundle, locale: L10n.locale)
        case .transport:
            String(localized: "Couldn't reach the e-service. Check your connection.", bundle: L10n.bundle, locale: L10n.locale)
        case .invalidSpec:
            String(localized: "Fixa's settings for this municipality are broken. Please update the app.", bundle: L10n.bundle, locale: L10n.locale)
        case .uncertain:
            String(localized: "The connection dropped just as the report went out, so Fixa didn't see a confirmation.", bundle: L10n.bundle, locale: L10n.locale)
        case .blocked:
            String(localized: "Värmdö kommun's e-service isn't taking reports from Fixa right now. Use the kommun's website.", bundle: L10n.bundle, locale: L10n.locale)
        case .loginRequired:
            String(localized: "Värmdö kommun's e-service now asks you to log in. Use the kommun's website.", bundle: L10n.bundle, locale: L10n.locale)
        }
    }
}
