import SwiftUI
import UIKit

/// The first-launch disclaimer: who runs Fixa, where the report goes, what stays on the phone.
/// Shown once as a full-screen cover from the root (UserDefaults `fixa.onboarded`), again from
/// About › How Fixa works. Scrolls at accessibility sizes; leading alignment keeps it right in RTL.
struct OnboardingScreen: View {
    @Environment(AppModel.self) private var model
    @State private var isLanguagePresented = false

    @ScaledMetric(relativeTo: .largeTitle) private var iconSide: CGFloat = 72

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Fx.Space.l) {
                appIcon
                    .padding(.top, Fx.Space.xl)

                Text(verbatim: "Fixa")
                    .font(Fx.Font.largeTitle)
                    .foregroundStyle(Fx.Color.ink)
                    .accessibilityAddTraits(.isHeader)

                FxCard {
                    FxIconRow(
                        systemImage: "building.columns",
                        text: String(localized: "An independent app. Not run by the municipality.", bundle: L10n.bundle, locale: L10n.locale)
                    )
                    FxDivider()
                    FxIconRow(
                        systemImage: "paperplane",
                        text: String(localized: "Your report goes straight to the municipality's own fault-report service, just like the website.", bundle: L10n.bundle, locale: L10n.locale)
                    )
                    FxDivider()
                    FxIconRow(
                        systemImage: "iphone",
                        text: String(localized: "No account. Your details stay on this phone.", bundle: L10n.bundle, locale: L10n.locale)
                    )
                    FxDivider()
                    FxIconRow(
                        systemImage: "hand.raised",
                        text: String(localized: "Nothing is sent until you press Send.", bundle: L10n.bundle, locale: L10n.locale)
                    )
                }

                FxIconRow(systemImage: "phone", text: String(localized: "In an emergency, call 112.", bundle: L10n.bundle, locale: L10n.locale))

                languageChip
            }
            .padding(.horizontal, Fx.Space.l)
            .padding(.bottom, Fx.Space.l)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .fxScreenBackground()
        .fxBottomBar {
            FxPrimaryButton(title: String(localized: "Continue", bundle: L10n.bundle, locale: L10n.locale)) {
                model.finishOnboarding()
            }
            .accessibilityIdentifier("onboarding.continue")
        }
        .interactiveDismissDisabled()
        .sheet(isPresented: $isLanguagePresented) {
            NavigationStack {
                SettingsLanguageScreen()
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button {
                                isLanguagePresented = false
                            } label: {
                                Text("Done")
                            }
                        }
                    }
            }
        }
    }

    /// The real icon from the bundle; a sea badge if iOS doesn't expose it.
    @ViewBuilder
    private var appIcon: some View {
        if let image = Self.iconImage {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(width: iconSide, height: iconSide)
                .clipShape(.rect(cornerRadius: iconSide * 0.225, style: .continuous))
                .accessibilityHidden(true)
        } else {
            FxBadge(systemImage: "wrench.adjustable", fill: Fx.Color.sea.opacity(0.15), side: iconSide)
                .accessibilityHidden(true)
        }
    }

    private static let iconImage: UIImage? = {
        if let icons = Bundle.main.infoDictionary?["CFBundleIcons"] as? [String: Any],
           let primary = icons["CFBundlePrimaryIcon"] as? [String: Any],
           let files = primary["CFBundleIconFiles"] as? [String],
           let name = files.last,
           let image = UIImage(named: name) {
            return image
        }
        return UIImage(named: "AppIcon")
    }()

    /// The current language in its own script, so a newcomer can switch first. Later it lives in Settings.
    private var languageChip: some View {
        let language = model.effectiveLanguage
        return Button {
            isLanguagePresented = true
        } label: {
            Label {
                Text(verbatim: language.nativeName)
                    .environment(\.locale, language.locale)
            } icon: {
                Image(systemName: "globe")
            }
            .font(Fx.Font.subheadline)
            .foregroundStyle(Fx.Color.sea)
            .padding(.horizontal, Fx.Space.m)
            .frame(minHeight: Fx.minTarget)
            .fxOutline(Capsule(), outline: Fx.Color.fieldBorder)
            .contentShape(Capsule())
        }
        .buttonStyle(FxPressStyle())
        .accessibilityLabel(Text("Language: \(language.nativeName)"))
        .accessibilityInputLabels([Text("Language"), Text(verbatim: language.nativeName)])
    }
}
