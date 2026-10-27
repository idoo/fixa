import FixaKit
import Foundation
import SwiftUI

extension ValidationIssue {
    /// Short inline message under the field.
    var message: String {
        switch (field, code) {
        case (.category, _):
            String(localized: "Choose what kind of problem it is.", bundle: L10n.bundle, locale: L10n.locale)
        case (.description, .missing):
            String(localized: "Describe the problem in a few words.", bundle: L10n.bundle, locale: L10n.locale)
        case (.description, .tooShort):
            String(localized: "Describe the problem in a few more words.", bundle: L10n.bundle, locale: L10n.locale)
        case (.description, .tooLong):
            String(localized: "This is too long for the e-service. Shorten it a little.", bundle: L10n.bundle, locale: L10n.locale)
        case (.location, .outsideRegion):
            String(localized: "This place is outside the municipality.", bundle: L10n.bundle, locale: L10n.locale)
        case (.location, _):
            String(localized: "Show where the problem is.", bundle: L10n.bundle, locale: L10n.locale)
        case (.email, .missing):
            String(localized: "Add your e-mail so they can reply.", bundle: L10n.bundle, locale: L10n.locale)
        case (.email, _):
            String(localized: "This e-mail address doesn't look right.", bundle: L10n.bundle, locale: L10n.locale)
        case (.phone, _):
            String(localized: "This phone number doesn't look right.", bundle: L10n.bundle, locale: L10n.locale)
        default:
            String(localized: "Check this field.", bundle: L10n.bundle, locale: L10n.locale)
        }
    }
}

extension SubmissionError {
    /// Sending through Fixa won't work until something outside the resident's hands changes, so the
    /// kommun's own website is the way through. Never for an uncertain send: that would file it twice.
    var offersWebForm: Bool {
        switch self {
        case .formChanged, .invalidSpec, .blocked, .loginRequired:
            true
        case .serverValidation(let messages):
            // With the e-service's own messages the resident can fix the report; without them they can't.
            messages.isEmpty
        default:
            false
        }
    }
}

extension AppModel.SendsPause {
    var message: String {
        switch self {
        case .blocked:
            String(localized: "The e-service isn't taking reports from Fixa at the moment. You can use the kommun's website instead.", bundle: L10n.bundle, locale: L10n.locale)
        case .loginRequired:
            String(localized: "The e-service now asks you to sign in. Fixa can't do that, so use the kommun's website instead.", bundle: L10n.bundle, locale: L10n.locale)
        case .serviceDown:
            String(localized: "Fixa has paused sending for now. You can use the kommun's website instead.", bundle: L10n.bundle, locale: L10n.locale)
        }
    }
}

/// "Open the kommun's website": copies the Swedish report text and opens the kommun's own form,
/// where the resident pastes it and adds the photo. For water and sewer the acute way, a call,
/// comes first: the kommun takes acute water faults by phone only.
struct WebFormFallback: View {
    /// The report text in Swedish; nil when there is nothing left to copy.
    let text: String?
    let spec: AdapterSpec
    let tileID: String?
    @Environment(AppModel.self) private var model

    var body: some View {
        if let text {
            VStack(alignment: .leading, spacing: Fx.Space.s) {
                if spec.tile(id: tileID)?.categoryID == "water", let emergency = spec.emergency {
                    Text("Acute water or sewer problem? Call \(EmergencyRouter.contact(for: .now, emergency: emergency).phone.ltrIsolated) instead.")
                        .font(Fx.Font.callout.weight(.semibold))
                        .foregroundStyle(Fx.Color.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
                FxSecondaryButton(title: String(localized: "Open the kommun's website", bundle: L10n.bundle, locale: L10n.locale), systemImage: "safari") {
                    model.openWebForm(text)
                }
                Text("The report text is copied. Paste it into the form and add the photo there.")
                    .font(Fx.Font.footnote)
                    .foregroundStyle(Fx.Color.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
