import FixaKit
import Foundation

extension ValidationIssue {
    /// Short inline message under the field.
    var message: String {
        switch (field, code) {
        case (.category, _):
            String(localized: "Choose what kind of problem it is.")
        case (.description, .missing):
            String(localized: "Describe the problem in a few words.")
        case (.description, .tooShort):
            String(localized: "Add a little more detail.")
        case (.description, .tooLong):
            String(localized: "This is too long for the e-service. Shorten it a little.")
        case (.location, .outsideRegion):
            String(localized: "This place is outside the municipality.")
        case (.location, _):
            String(localized: "Show where the problem is.")
        case (.email, .missing):
            String(localized: "Add your e-mail so they can reply.")
        case (.email, _):
            String(localized: "This e-mail address doesn't look right.")
        case (.phone, _):
            String(localized: "This phone number doesn't look right.")
        default:
            String(localized: "Check this field.")
        }
    }
}
