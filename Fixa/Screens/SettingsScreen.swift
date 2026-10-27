import FixaKit
import SwiftUI

/// One place for contact details, language, display and about. Every display setting starts at
/// "follow the iPhone"; changes apply at once from the root (`RootView`).
struct SettingsScreen: View {
    @Environment(AppModel.self) private var model
    @Environment(\.fxHaptics) private var haptics
    @State private var isClearHistoryPresented = false
    @State private var isDeleteAllPresented = false
    /// Bumped after "Delete all my data": shows the banner and plays the success haptic.
    @State private var deletions = 0
    /// Set to start "Report a problem with the app" (an e-mail the user sees before sending).
    @State private var developerReport: DeveloperReport?

    var body: some View {
        @Bindable var model = model
        ScrollView {
            VStack(alignment: .leading, spacing: Fx.Space.xl) {
                section(String(localized: "Your details", bundle: L10n.bundle, locale: L10n.locale)) {
                    SettingsNavRow(
                        systemImage: "envelope",
                        title: String(localized: "Contact details", bundle: L10n.bundle, locale: L10n.locale),
                        value: contactSummary
                    ) {
                        model.path.append(.contactDetails)
                    }
                    FxDivider()
                    FxToggleRow(
                        title: String(localized: "Remember my details", bundle: L10n.bundle, locale: L10n.locale),
                        subtitle: model.rememberDetails
                            ? String(localized: "Saved on this phone for your next report.", bundle: L10n.bundle, locale: L10n.locale)
                            : String(localized: "Used only for the report you're writing, then forgotten.", bundle: L10n.bundle, locale: L10n.locale),
                        isOn: $model.rememberDetails
                    )
                }

                section(String(localized: "Language", bundle: L10n.bundle, locale: L10n.locale)) {
                    SettingsNavRow(
                        systemImage: "globe",
                        title: String(localized: "Language", bundle: L10n.bundle, locale: L10n.locale),
                        value: model.effectiveLanguage.nativeName
                    ) {
                        model.path.append(.language)
                    }
                    .accessibilityIdentifier("settings.language")
                }

                section(String(localized: "Display", bundle: L10n.bundle, locale: L10n.locale)) {
                    SettingsNavRow(
                        systemImage: "textformat.size",
                        title: String(localized: "Text size", bundle: L10n.bundle, locale: L10n.locale),
                        value: textSizeSummary
                    ) {
                        model.path.append(.textSize)
                    }
                    FxDivider()
                    AppearancePicker(appearance: $model.display.appearance)
                    FxDivider()
                    FxToggleRow(title: String(localized: "Bold text", bundle: L10n.bundle, locale: L10n.locale), isOn: $model.display.boldText)
                    FxDivider()
                    FxToggleRow(
                        title: String(localized: "Higher contrast", bundle: L10n.bundle, locale: L10n.locale),
                        subtitle: String(localized: "Darker borders and text", bundle: L10n.bundle, locale: L10n.locale),
                        isOn: $model.display.higherContrast
                    )
                    FxDivider()
                    FxToggleRow(
                        title: String(localized: "Reduce motion", bundle: L10n.bundle, locale: L10n.locale),
                        subtitle: String(localized: "Fewer moving effects", bundle: L10n.bundle, locale: L10n.locale),
                        isOn: $model.display.reduceMotion
                    )
                    FxDivider()
                    FxToggleRow(
                        title: String(localized: "Vibration", bundle: L10n.bundle, locale: L10n.locale),
                        subtitle: String(localized: "Small taps when you press buttons", bundle: L10n.bundle, locale: L10n.locale),
                        isOn: $model.display.vibration
                    )
                }

                privacySection

                section(String(localized: "About", bundle: L10n.bundle, locale: L10n.locale)) {
                    SettingsNavRow(
                        systemImage: "info.circle",
                        title: String(localized: "About Fixa", bundle: L10n.bundle, locale: L10n.locale),
                        value: nil
                    ) {
                        model.path.append(.about)
                    }
                    FxDivider()
                    FxIconRow(
                        systemImage: "hand.raised",
                        text: String(localized: "Privacy policy", bundle: L10n.bundle, locale: L10n.locale),
                        link: Self.privacyPolicyURL
                    )
                    FxDivider()
                    SettingsNavRow(
                        systemImage: "envelope.badge",
                        title: String(localized: "Report a problem with the app", bundle: L10n.bundle, locale: L10n.locale),
                        value: String(localized: "An e-mail to the developer. You see it before it's sent.", bundle: L10n.bundle, locale: L10n.locale)
                    ) {
                        developerReport = DeveloperReport(spec: model.spec, error: model.submission.error)
                    }
                    .accessibilityIdentifier("settings.reportProblem")
                    FxDivider()
                    FxIconRow(systemImage: "number", text: versionText)
                }
            }
            .padding(Fx.Space.l)
        }
        .fxScreenBackground()
        .navigationTitle(Text("Settings"))
        .navigationBarTitleDisplayMode(.inline)
        .sensoryFeedback(.success, trigger: deletions) { _, _ in haptics }
        .developerReport($developerReport)
    }

    private var privacySection: some View {
        let sentCount = model.history.items.count
        return section(String(localized: "Privacy", bundle: L10n.bundle, locale: L10n.locale)) {
            SettingsNavRow(
                systemImage: "lock",
                title: String(localized: "What Fixa stores", bundle: L10n.bundle, locale: L10n.locale),
                value: nil
            ) {
                model.path.append(.privacy)
            }
            FxDivider()
            SettingsActionRow(
                systemImage: "clock.arrow.circlepath",
                title: String(localized: "Clear sent reports", bundle: L10n.bundle, locale: L10n.locale),
                value: sentCount.formatted(.number.locale(L10n.locale)),
                tint: Fx.Color.sea
            ) {
                isClearHistoryPresented = true
            }
            .disabled(sentCount == 0)
            .confirmationDialog(
                Text("Clear the list of sent reports?"),
                isPresented: $isClearHistoryPresented,
                titleVisibility: .visible
            ) {
                Button(role: .destructive) {
                    model.clearHistory()
                } label: {
                    Text("Clear list")
                }
                Button(role: .cancel) {} label: {
                    Text("Cancel")
                }
            } message: {
                Text(clearHistoryMessage(count: sentCount))
            }
            FxDivider()
            SettingsActionRow(
                systemImage: "trash",
                title: String(localized: "Delete all my data", bundle: L10n.bundle, locale: L10n.locale),
                value: nil,
                tint: Fx.Color.error
            ) {
                isDeleteAllPresented = true
            }
            .accessibilityIdentifier("settings.deleteAll")
            // A report on its way keeps its data until it is sent.
            .disabled(model.isBusySending)
            .confirmationDialog(
                Text("Delete all your data from this phone?"),
                isPresented: $isDeleteAllPresented,
                titleVisibility: .visible
            ) {
                Button(role: .destructive) {
                    model.deleteAllData()
                    deletions += 1
                } label: {
                    Text("Delete all data")
                }
                Button(role: .cancel) {} label: {
                    Text("Cancel")
                }
            } message: {
                Text("This deletes your contact details, your unsent report and the list of sent reports, including their photos. Reports already sent to \(model.spec?.municipality.name ?? "") are not affected. Your language and display settings stay. This can't be undone.")
            }
            if deletions > 0 {
                FxDivider()
                FxBanner(kind: .success, title: String(localized: "Your data is deleted from this phone.", bundle: L10n.bundle, locale: L10n.locale))
                    .padding(.vertical, Fx.Space.s)
            }
        }
    }

    /// One report reads as one; more use the count. Translations keep the count-led phrasing
    /// where a language has more plural forms.
    private func clearHistoryMessage(count: Int) -> String {
        let municipality = model.spec?.municipality.name ?? ""
        if count == 1 {
            return String(localized: "1 report is removed from this phone, with its case number. \(municipality) still has it.", bundle: L10n.bundle, locale: L10n.locale)
        }
        return String(localized: "\(count) reports are removed from this phone, with their case numbers. \(municipality) still has them.", bundle: L10n.bundle, locale: L10n.locale)
    }

    static let privacyPolicyURL = URL(string: "https://github.com/idoo/fixa/blob/main/PRIVACY.md")!

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Fx.Space.s) {
            Text(title)
                .font(Fx.Font.headline)
                .foregroundStyle(Fx.Color.ink)
                .accessibilityAddTraits(.isHeader)
            FxCard {
                content()
            }
        }
    }

    private var contactSummary: String {
        let email = model.profile.email.trimmingCharacters(in: .whitespacesAndNewlines)
        return email.isEmpty ? String(localized: "Not added", bundle: L10n.bundle, locale: L10n.locale) : email
    }

    private var textSizeSummary: String {
        guard let step = model.display.textSize else { return String(localized: "iPhone setting", bundle: L10n.bundle, locale: L10n.locale) }
        return String(localized: "Size \(step.number) of \(TextSizeStep.allCases.count)", bundle: L10n.bundle, locale: L10n.locale)
    }

    private var versionText: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return String(localized: "Version \(version) (\(build))", bundle: L10n.bundle, locale: L10n.locale)
    }
}

/// Whole-row button: glyph, title, current value and a forward chevron. At least 44 pt tall.
struct SettingsNavRow: View {
    let systemImage: String
    let title: String
    let value: String?
    let action: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .body) private var iconColumn: CGFloat = 28

    var body: some View {
        Button(action: action) {
            HStack(spacing: Fx.Space.m) {
                Image(systemName: systemImage)
                    .font(Fx.Font.body)
                    .foregroundStyle(Fx.Color.sea)
                    .frame(width: iconColumn)
                    .accessibilityHidden(true)
                // Title on top, current value underneath: long values (an e-mail address) never
                // break the title or wrap mid-word beside it.
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(Fx.Font.body)
                        .foregroundStyle(Fx.Color.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    if let value {
                        Text(value)
                            .font(Fx.Font.callout)
                            .foregroundStyle(Fx.Color.ink2)
                            .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 1)
                            .truncationMode(.middle)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.forward")
                    .font(Fx.Font.footnote.weight(.semibold))
                    .foregroundStyle(Fx.Color.ink2)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: Fx.minTarget)
            .contentShape(.rect)
        }
        .buttonStyle(FxPressStyle())
        .accessibilityElement(children: .combine)
    }
}

/// Whole-row action button: tinted glyph and title, optional trailing value, no chevron.
private struct SettingsActionRow: View {
    let systemImage: String
    let title: String
    let value: String?
    let tint: Color
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled
    @ScaledMetric(relativeTo: .body) private var iconColumn: CGFloat = 28

    var body: some View {
        Button(action: action) {
            HStack(spacing: Fx.Space.m) {
                Image(systemName: systemImage)
                    .font(Fx.Font.body)
                    .frame(width: iconColumn)
                    .accessibilityHidden(true)
                Text(title)
                    .font(Fx.Font.body.weight(.semibold))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                if let value {
                    Text(verbatim: value)
                        .font(Fx.Font.body)
                        .foregroundStyle(Fx.Color.ink2)
                }
            }
            .foregroundStyle(isEnabled ? tint : Fx.Color.ink2)
            .frame(minHeight: Fx.minTarget)
            .contentShape(.rect)
        }
        .buttonStyle(FxPressStyle())
        .accessibilityElement(children: .combine)
    }
}

/// Automatic / Light / Dark: segmented normally, three radio rows at accessibility text sizes.
private struct AppearancePicker: View {
    @Binding var appearance: DisplaySettings.Appearance
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.fxHaptics) private var haptics

    var body: some View {
        VStack(alignment: .leading, spacing: Fx.Space.s) {
            Text("Appearance")
                .font(Fx.Font.body)
                .foregroundStyle(Fx.Color.ink)
            if dynamicTypeSize.isAccessibilitySize {
                ForEach(DisplaySettings.Appearance.allCases, id: \.self) { option in
                    Button {
                        appearance = option
                    } label: {
                        HStack(spacing: Fx.Space.m) {
                            Image(systemName: appearance == option ? "largecircle.fill.circle" : "circle")
                                .foregroundStyle(appearance == option ? Fx.Color.sea : Fx.Color.ink2)
                                .accessibilityHidden(true)
                            Text(Self.title(option))
                                .font(Fx.Font.body)
                                .foregroundStyle(Fx.Color.ink)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(minHeight: Fx.minTarget)
                        .contentShape(.rect)
                    }
                    .buttonStyle(FxPressStyle())
                    .accessibilityAddTraits(appearance == option ? .isSelected : [])
                }
            } else {
                Picker(selection: $appearance) {
                    ForEach(DisplaySettings.Appearance.allCases, id: \.self) { option in
                        Text(Self.title(option)).tag(option)
                    }
                } label: {
                    Text("Appearance")
                }
                .pickerStyle(.segmented)
                .frame(minHeight: Fx.minTarget)
            }
        }
        .sensoryFeedback(.selection, trigger: appearance) { _, _ in haptics }
    }

    static func title(_ appearance: DisplaySettings.Appearance) -> String {
        switch appearance {
        case .automatic: String(localized: "Automatic", bundle: L10n.bundle, locale: L10n.locale)
        case .light: String(localized: "Light", bundle: L10n.bundle, locale: L10n.locale)
        case .dark: String(localized: "Dark", bundle: L10n.bundle, locale: L10n.locale)
        }
    }
}
