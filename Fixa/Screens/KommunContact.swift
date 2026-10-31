import FixaKit
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// "Not sure it arrived? Ask the kommun": for a report that may not have arrived. Copies `reference`
/// (when given) and opens the kommun's contact page in the in-app Safari view; Fixa never calls the
/// kommun for this. Empty when the adapter has no contact page.
struct ServiceCentreHelp: View {
    let spec: AdapterSpec
    var alignment: TextAlignment = .leading
    /// What the resident can paste into their question, e.g. the report's time and problem.
    var reference: String? = nil

    var body: some View {
        KommunAskRow(
            spec: spec,
            text: String(localized: "Not sure it arrived? Ask the kommun", bundle: L10n.bundle, locale: L10n.locale),
            copyText: reference,
            alignment: alignment
        )
    }
}

/// "Questions about this report? Ask the kommun" in a sent report: copies the case number (if any)
/// and opens the kommun's contact page in the in-app Safari view. Empty without a contact page.
struct KommunCaseContact: View {
    let spec: AdapterSpec
    let caseNumber: String?

    init(spec: AdapterSpec, caseNumber: String?) {
        self.spec = spec
        self.caseNumber = caseNumber
    }

    var body: some View {
        KommunAskRow(
            spec: spec,
            text: String(localized: "Questions about this report? Ask the kommun", bundle: L10n.bundle, locale: L10n.locale),
            copyText: caseNumber,
            alignment: .leading
        )
    }
}

/// The shared row: tap copies `copyText` (this phone only, for an hour), shows that it did, and opens
/// `spec.contact.pageURL`.
private struct KommunAskRow: View {
    let spec: AdapterSpec
    let text: String
    let copyText: String?
    let alignment: TextAlignment
    @State private var copied: String?

    var body: some View {
        if let contact = spec.contact {
            VStack(alignment: horizontal, spacing: Fx.Space.xs) {
                FxIconRow(systemImage: "bubble.left.and.text.bubble.right", text: text) {
                    if let copyText = copyText?.trimmingCharacters(in: .whitespacesAndNewlines), !copyText.isEmpty {
                        UIPasteboard.general.setItems(
                            [[UTType.utf8PlainText.identifier: copyText]],
                            options: [.localOnly: true, .expirationDate: Date.now.addingTimeInterval(60 * 60)]
                        )
                        copied = copyText
                    }
                    KommunWeb.open(contact.pageURL, spec: spec)
                }
                .accessibilityHint(Text("Opens \(contact.title.resolve(L10n.locale)) on the kommun's website"))
                .accessibilityIdentifier("kommun.ask")
                if let copied {
                    Label(String(localized: "Copied: \(copied). Paste it in your message.", bundle: L10n.bundle, locale: L10n.locale), systemImage: "doc.on.doc")
                        .font(Fx.Font.footnote)
                        .foregroundStyle(Fx.Color.ink2)
                        .multilineTextAlignment(alignment)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("kommun.ask.copied")
                }
            }
            .frame(maxWidth: .infinity, alignment: Alignment(horizontal: horizontal, vertical: .center))
        }
    }

    private var horizontal: HorizontalAlignment {
        switch alignment {
        case .center: .center
        case .trailing: .trailing
        default: .leading
        }
    }
}
