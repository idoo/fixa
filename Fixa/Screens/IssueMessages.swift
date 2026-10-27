import FixaKit
import Foundation

extension ValidationIssue {
    /// Short inline message under the field.
    var message: String {
        switch (field, code) {
        case (.category, _):
            String(localized: "Choose what kind of problem it is.", bundle: L10n.bundle, locale: L10n.locale)
        case (.description, .missing):
            String(localized: "Describe the problem in a few words.", bundle: L10n.bundle, locale: L10n.locale)
        case (.description, .tooShort):
            String(localized: "Write a few more words (at least 10 letters).", bundle: L10n.bundle, locale: L10n.locale)
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
