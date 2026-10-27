import FixaKit
import SwiftUI

/// Contact details for replies (Settings › Your details). Saved on this phone as you type while
/// "Remember my details" is on; otherwise used only for the report being written.
struct ProfileScreen: View {
    @Environment(AppModel.self) private var model
    @Environment(\.fxReduceMotion) private var reduceMotion
    @Environment(\.fxHaptics) private var haptics
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var isConfirmingClear = false
    /// Inline problems show once there is something to judge: a saved profile, or after Return.
    @State private var showIssues = false
    @State private var clears = 0

    var body: some View {
        @Bindable var model = model
        let issues = showIssues ? model.contactIssues(model.profile) : []
        let nameLayout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Fx.Space.m))
            : AnyLayout(HStackLayout(alignment: .top, spacing: Fx.Space.s))
        ScrollView {
            VStack(alignment: .leading, spacing: Fx.Space.l) {
                Group {
                    if model.rememberDetails {
                        Text("Optional. Only used when you ask for a reply. Saved on this phone.")
                    } else {
                        Text("Optional. Only used when you ask for a reply, for the report you're writing.")
                    }
                }
                .font(Fx.Font.callout)
                .foregroundStyle(Fx.Color.ink2)
                .fixedSize(horizontal: false, vertical: true)

                FxTextField(
                    title: String(localized: "E-mail", bundle: L10n.bundle, locale: L10n.locale),
                    text: $model.profile.email,
                    prompt: String(localized: "name@example.com", bundle: L10n.bundle, locale: L10n.locale),
                    kind: .email,
                    issue: issues.first { $0.field == .email }?.message
                )
                nameLayout {
                    FxTextField(
                        title: String(localized: "First name (optional)", bundle: L10n.bundle, locale: L10n.locale),
                        text: $model.profile.firstName
                    )
                    FxTextField(
                        title: String(localized: "Last name (optional)", bundle: L10n.bundle, locale: L10n.locale),
                        text: $model.profile.lastName
                    )
                }
                FxTextField(
                    title: String(localized: "Phone (optional)", bundle: L10n.bundle, locale: L10n.locale),
                    text: $model.profile.phone,
                    kind: .phone,
                    issue: issues.first { $0.field == .phone }?.message
                )

                if !model.profileIsEmpty && model.rememberDetails {
                    Label("Saved on this phone", systemImage: "checkmark.circle")
                        .font(Fx.Font.footnote)
                        .foregroundStyle(Fx.Color.ink2)
                        .transition(.opacity)
                }

                Button(role: .destructive) {
                    isConfirmingClear = true
                } label: {
                    Label("Clear my details", systemImage: "trash")
                        .font(Fx.Font.callout.weight(.semibold))
                        .foregroundStyle(model.profileIsEmpty ? Fx.Color.ink2 : Fx.Color.error)
                        .frame(minHeight: Fx.minTarget)
                }
                .buttonStyle(FxPressStyle())
                .disabled(model.profileIsEmpty)
            }
            .padding(Fx.Space.l)
            .animation(reduceMotion ? .easeInOut(duration: 0.15) : Fx.Motion.select, value: model.profileIsEmpty)
        }
        .scrollDismissesKeyboard(.interactively)
        .fxScreenBackground()
        .navigationTitle(Text("Contact details"))
        .navigationBarTitleDisplayMode(.inline)
        .sensoryFeedback(.success, trigger: clears) { _, _ in haptics }
        .onSubmit { showIssues = true }
        .onAppear { showIssues = !model.profileIsEmpty }
        .onDisappear { model.saveProfileNow() }
        .confirmationDialog(
            Text("Clear your details?"),
            isPresented: $isConfirmingClear,
            titleVisibility: .visible
        ) {
            Button("Clear my details", role: .destructive) {
                model.clearProfile()
                showIssues = false
                clears += 1
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your e-mail, name and phone are removed from this phone, and new reports won't ask for a reply. Reports you already sent keep them.")
        }
    }
}
