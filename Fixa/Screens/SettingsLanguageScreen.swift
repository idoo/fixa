import FixaKit
import SwiftUI

/// "Same as iPhone" plus the six UI languages, each written in its own script with its name in the
/// current language underneath. The choice is saved at once (UserDefaults `fixa.language`).
struct SettingsLanguageScreen: View {
    @Environment(AppModel.self) private var model
    @Environment(\.locale) private var locale
    @Environment(\.fxHaptics) private var haptics

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Fx.Space.l) {
                FxCard {
                    row(
                        title: String(localized: "Same as iPhone (\(AppLanguage.system.nativeName))"),
                        subtitle: nil,
                        language: nil
                    )
                    ForEach(AppLanguage.allCases) { language in
                        FxDivider()
                        row(
                            title: language.nativeName,
                            subtitle: language.name(in: locale),
                            language: language
                        )
                        .environment(\.locale, language.locale)
                        .typesettingLanguage(Locale.Language(identifier: language.rawValue))
                    }
                }

                Text("Fixa's buttons and texts change now. What you write is sent as you wrote it. The photo picker and permission questions follow the new language next time you open Fixa.")
                    .font(Fx.Font.footnote)
                    .foregroundStyle(Fx.Color.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(Fx.Space.l)
        }
        .fxScreenBackground()
        .navigationTitle(Text("Language"))
        .navigationBarTitleDisplayMode(.inline)
        .sensoryFeedback(.selection, trigger: model.language) { _, _ in haptics }
    }

    private func row(title: String, subtitle: String?, language: AppLanguage?) -> some View {
        let isSelected = model.language == language
        return Button {
            model.language = language
        } label: {
            HStack(spacing: Fx.Space.m) {
                VStack(alignment: .leading, spacing: Fx.Space.xs) {
                    Text(verbatim: title)
                        .font(Fx.Font.body)
                        .foregroundStyle(Fx.Color.ink)
                    if let subtitle, subtitle != title {
                        Text(verbatim: subtitle)
                            .font(Fx.Font.footnote)
                            .foregroundStyle(Fx.Color.ink2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(Fx.Font.headline)
                        .foregroundStyle(Fx.Color.sea)
                        .accessibilityHidden(true)
                }
            }
            .frame(minHeight: Fx.minTarget)
            .contentShape(.rect)
        }
        .buttonStyle(FxPressStyle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
