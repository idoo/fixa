import FixaKit
import SwiftUI
import Translation

/// The kommun's Swedish in the app's language: known sentences from Fixa's own translations
/// (`KommunPhrasebook`), the rest translated on the phone. Swedish UI shows the Swedish as is.
nonisolated enum KommunText {
    static func fields(_ spec: AdapterSpec?) -> [AdapterSpec.FieldSpec] {
        spec?.channel.pages.flatMap(\.fields) ?? []
    }

    /// Known sentences translated, unknown ones left in Swedish; for VoiceOver announcements and
    /// other places that need one plain string. Swedish UI: the text unchanged.
    static func plain(_ swedish: String, spec: AdapterSpec?) -> String {
        guard L10n.effectiveLanguage.rawValue != "sv" else { return swedish }
        return text(of: KommunPhrasebook.read(swedish, fields: fields(spec))) { $0 }
    }

    /// The reading as lines, unknown parts passed through `unknown` (their translation, if any).
    static func text(of reading: KommunReading, unknown: (String) -> String) -> String {
        reading.lines.map { parts in
            parts.map { part in
                switch part {
                case .phrase(let phrase): localized(phrase)
                case .unknown(let swedish): unknown(swedish)
                }
            }
            .joined(separator: " ")
        }
        .joined(separator: "\n")
    }

    static func localized(_ phrase: KommunPhrase) -> String {
        switch phrase.id {
        case .thanksForUsingService:
            return String(localized: "Thank you for using our e-service!", bundle: L10n.bundle, locale: L10n.locale)
        case .caseNumber:
            // Left-to-right isolates keep the number's order inside Arabic text (as `ltrIsolated`).
            let number = "\u{2066}\(phrase[.caseNumber] ?? "")\u{2069}"
            return String(localized: "Here is your case number: \(number)", bundle: L10n.bundle, locale: L10n.locale)
        case .thanksForReport:
            return String(localized: "Thank you for your fault report!", bundle: L10n.bundle, locale: L10n.locale)
        case .regards:
            return String(localized: "Kind regards", bundle: L10n.bundle, locale: L10n.locale)
        case .signature:
            // A name; never translated.
            return phrase[.name] ?? phrase.original
        case .replyWithinWorkingDays:
            let days = phrase[.days] ?? ""
            return String(localized: "If you asked for a reply, you will get an answer within \(days) working days.", bundle: L10n.bundle, locale: L10n.locale)
        case .longerHandlingTime:
            return String(localized: "If your question takes longer to handle, we confirm within the same time that we have received your case, and tell you who is handling it.", bundle: L10n.bundle, locale: L10n.locale)
        case .processing:
            return String(localized: "Your details are being processed. Please wait…", bundle: L10n.bundle, locale: L10n.locale)
        case .chooseValue:
            return String(localized: "Choose an answer for “\(fieldName(phrase))”.", bundle: L10n.bundle, locale: L10n.locale)
        case .fillIn:
            return String(localized: "Fill in “\(fieldName(phrase))”.", bundle: L10n.bundle, locale: L10n.locale)
        }
    }

    /// The field a validation message names, as Fixa calls it; the kommun's own label when unknown.
    private static func fieldName(_ phrase: KommunPhrase) -> String {
        let label = phrase[.label] ?? ""
        guard let role = phrase[.role].flatMap(AdapterSpec.FieldSpec.Role.init(rawValue:)) else { return label }
        return switch role {
        case .category: String(localized: "Category", bundle: L10n.bundle, locale: L10n.locale)
        case .place, .mapChoice, .mapAnswer: String(localized: "Place", bundle: L10n.bundle, locale: L10n.locale)
        case .description: String(localized: "Description", bundle: L10n.bundle, locale: L10n.locale)
        case .feedback: String(localized: "Reply", bundle: L10n.bundle, locale: L10n.locale)
        case .firstName: String(localized: "First name", bundle: L10n.bundle, locale: L10n.locale)
        case .lastName: String(localized: "Last name", bundle: L10n.bundle, locale: L10n.locale)
        case .phone: String(localized: "Phone", bundle: L10n.bundle, locale: L10n.locale)
        case .email: String(localized: "E-mail", bundle: L10n.bundle, locale: L10n.locale)
        }
    }
}

/// What the kommun's e-service said, in the app's language, with the kommun's exact Swedish one tap
/// away ("Show original"). Known sentences use Fixa's translations; unknown ones are translated on
/// the phone (Apple Translation, Swedish → app language), or stay Swedish with a note when the phone
/// can't. Swedish UI: the Swedish only, no toggle.
struct KommunTextView: View {
    let swedish: String
    var spec: AdapterSpec? = nil
    /// Attribution above the text, e.g. "Värmdö kommun's receipt".
    var title: String? = nil
    /// A thin rule on the leading edge marks the text as a quote (receipt, Sent reports).
    var quoted = true

    @State private var showsOriginal = false
    @State private var translations: [String: String] = [:]
    @State private var state: TranslationState = .idle
    @State private var configuration: TranslationSession.Configuration?

    private enum TranslationState: Equatable {
        case idle, translating, done, unavailable
    }

    /// Unknown text waits at most this long for the phone's translation, then stays Swedish.
    private static let translationCap: Duration = .seconds(15)
    private static let swedishLanguage = Locale.Language(identifier: "sv")

    private var isSwedishUI: Bool { L10n.effectiveLanguage == .sv }

    private var reading: KommunReading {
        KommunPhrasebook.read(swedish, fields: KommunText.fields(spec))
    }

    var body: some View {
        let content = VStack(alignment: .leading, spacing: Fx.Space.xs) {
            if let title {
                Text(title)
                    .font(Fx.Font.footnote.weight(.semibold))
                    .foregroundStyle(Fx.Color.ink2)
            }
            if isSwedishUI {
                swedishText(font: Fx.Font.body)
            } else {
                translated
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)

        Group {
            if quoted {
                content
                    .padding(.leading, Fx.Space.m)
                    .overlay(alignment: .leading) {
                        Rectangle()
                            .fill(Fx.Color.line)
                            .frame(width: 2)
                    }
            } else {
                content
            }
        }
        .task(id: swedish) { await prepare() }
        .translationTask(configuration) { session in
            await translate(with: session)
        }
        .task(id: state) {
            guard state == .translating,
                  (try? await Task.sleep(for: Self.translationCap)) != nil,
                  state == .translating else { return }
            state = .unavailable
        }
    }

    @ViewBuilder
    private var translated: some View {
        let reading = reading
        VStack(alignment: .leading, spacing: Fx.Space.xs) {
            Text(KommunText.text(of: reading) { translations[$0] ?? $0 })
                .font(Fx.Font.body)
                .foregroundStyle(Fx.Color.ink)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
            Text(note(hasUnknown: !reading.unknown.isEmpty))
                .font(Fx.Font.footnote)
                .foregroundStyle(Fx.Color.ink2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        Button {
            showsOriginal.toggle()
        } label: {
            Label(
                showsOriginal
                    ? String(localized: "Hide original", bundle: L10n.bundle, locale: L10n.locale)
                    : String(localized: "Show original", bundle: L10n.bundle, locale: L10n.locale),
                systemImage: showsOriginal ? "chevron.up" : "text.quote"
            )
            .font(Fx.Font.footnote.weight(.bold))
            .foregroundStyle(Fx.Color.sea)
            .frame(minHeight: Fx.minTarget, alignment: .leading)
            .contentShape(.rect)
        }
        .buttonStyle(FxPressStyle())
        .accessibilityIdentifier("kommun.showOriginal")
        if showsOriginal {
            VStack(alignment: .leading, spacing: Fx.Space.xs) {
                Text("In Swedish, as the kommun wrote it")
                    .font(Fx.Font.footnote.weight(.semibold))
                    .foregroundStyle(Fx.Color.ink2)
                swedishText(font: Fx.Font.callout)
            }
            .accessibilityElement(children: .combine)
        }
    }

    private func swedishText(font: Font) -> some View {
        Text(swedish)
            .font(font)
            .foregroundStyle(Fx.Color.ink)
            .fixedSize(horizontal: false, vertical: true)
            .textSelection(.enabled)
            .environment(\.locale, Locale(identifier: "sv_SE"))
            .accessibilityTextContentType(.plain)
    }

    private func note(hasUnknown: Bool) -> String {
        guard hasUnknown else {
            return String(localized: "Translated from Swedish", bundle: L10n.bundle, locale: L10n.locale)
        }
        return switch state {
        case .idle, .translating:
            String(localized: "Translating on your phone…", bundle: L10n.bundle, locale: L10n.locale)
        case .done:
            String(localized: "Translated on your phone", bundle: L10n.bundle, locale: L10n.locale)
        case .unavailable:
            String(localized: "Some of this is in Swedish: your phone couldn't translate it.", bundle: L10n.bundle, locale: L10n.locale)
        }
    }

    /// Starts the phone's translation when there is unknown text and the language pair exists.
    private func prepare() async {
        translations = [:]
        guard !isSwedishUI, !reading.unknown.isEmpty else {
            state = .idle
            return
        }
        let target = Locale.Language(identifier: L10n.effectiveLanguage.rawValue)
        let status = await LanguageAvailability().status(from: Self.swedishLanguage, to: target)
        guard status != .unsupported else {
            state = .unavailable
            return
        }
        state = .translating
        if configuration?.target == target {
            configuration?.invalidate()
        } else {
            configuration = TranslationSession.Configuration(source: Self.swedishLanguage, target: target)
        }
    }

    /// If the download is declined or fails, the unknown text stays Swedish and the note says so.
    private func translate(with session: TranslationSession) async {
        let unknown = reading.unknown
        guard !unknown.isEmpty else { return }
        var requests: [TranslationSession.Request] = []
        for (index, text) in unknown.enumerated() {
            requests.append(TranslationSession.Request(sourceText: text, clientIdentifier: String(index)))
        }
        do {
            // The session belongs to this `.translationTask` call and is used only here (as in ReviewScreen).
            nonisolated(unsafe) let session = session
            let responses = try await session.translations(from: requests)
            var result: [String: String] = [:]
            for response in responses {
                guard let index = response.clientIdentifier.flatMap(Int.init), unknown.indices.contains(index) else { continue }
                let text = response.targetText.trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty { result[unknown[index]] = text }
            }
            translations = result
            state = result.count == unknown.count ? .done : .unavailable
        } catch {
            state = .unavailable
        }
    }
}

/// The exact Swedish the kommun's form got (or will get), folded away under the resident's own words.
struct FiledInSwedish: View {
    let text: String
    /// False while the report is still waiting on this phone.
    var isFiled = true
    @State private var isExpanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            Text(text)
                .font(Fx.Font.callout)
                .foregroundStyle(Fx.Color.ink)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
                .environment(\.locale, Locale(identifier: "sv_SE"))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, Fx.Space.xs)
        } label: {
            Text(isFiled
                ? String(localized: "Filed in Swedish", bundle: L10n.bundle, locale: L10n.locale)
                : String(localized: "Will be sent in Swedish", bundle: L10n.bundle, locale: L10n.locale))
                .font(Fx.Font.subheadline)
                .foregroundStyle(Fx.Color.ink2)
        }
        .tint(Fx.Color.sea)
        .accessibilityIdentifier("report.filedInSwedish")
    }
}
