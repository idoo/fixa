import SwiftUI

/// The first-launch disclaimer: who runs Fixa, where the report goes, what stays on the phone.
/// Shown once as a full-screen cover from the root (UserDefaults `fixa.onboarded`), again from
/// About › How Fixa works. Brand moment on top (the cone mark), then leading-aligned facts so RTL
/// reads right. Scrolls at accessibility sizes.
struct OnboardingScreen: View {
    @Environment(AppModel.self) private var model
    @State private var isLanguagePresented = false

    @ScaledMetric(relativeTo: .largeTitle) private var markSide: CGFloat = 88

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Fx.Space.l) {
                VStack(spacing: Fx.Space.m) {
                    FxBrandMark(size: min(markSide, 140))
                    VStack(spacing: Fx.Space.xs) {
                        Text(verbatim: "Fixa")
                            .font(Fx.Font.largeTitle)
                            .foregroundStyle(Fx.Color.ink)
                            .accessibilityAddTraits(.isHeader)
                        Text("Tell the kommun what's broken.")
                            .font(Fx.Font.callout)
                            .foregroundStyle(Fx.Color.ink2)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.top, Fx.Space.xxl)
                .padding(.bottom, Fx.Space.s)

                FxCard {
                    FxIconRow(
                        systemImage: "building.columns",
                        text: String(localized: "An independent app. Not run by the municipality.", bundle: L10n.bundle, locale: L10n.locale)
                    )
                    FxDivider()
                    FxIconRow(
                        systemImage: "paperplane",
                        text: String(localized: "Reports go straight to the kommun's own fault service.", bundle: L10n.bundle, locale: L10n.locale)
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
