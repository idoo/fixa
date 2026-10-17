import FixaKit
import SwiftUI

/// Optional reply details. Saved on this phone as you type; the report uses them when you ask for a reply.
struct ProfileScreen: View {
    @Environment(AppModel.self) private var model
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
                Text("Optional. Only used when you ask for a reply. Saved on this phone.")
                    .font(Fx.Font.callout)
                    .foregroundStyle(Fx.Color.ink2)
                    .fixedSize(horizontal: false, vertical: true)

                FxTextField(
                    title: String(localized: "E-mail"),
                    text: $model.profile.email,
                    prompt: String(localized: "name@example.com"),
                    kind: .email,
                    issue: issues.first { $0.field == .email }?.message
                )
                nameLayout {
                    FxTextField(
                        title: String(localized: "First name (optional)"),
                        text: $model.profile.firstName
                    )
                    FxTextField(
                        title: String(localized: "Last name (optional)"),
                        text: $model.profile.lastName
                    )
                }
                FxTextField(
                    title: String(localized: "Phone (optional)"),
                    text: $model.profile.phone,
                    kind: .phone,
                    issue: issues.first { $0.field == .phone }?.message
                )

                if !model.profileIsEmpty {
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
                .buttonStyle(FxPressStyle(dims: true))
                .disabled(model.profileIsEmpty)

                aboutRow
                    .padding(.top, Fx.Space.l)
            }
            .padding(Fx.Space.l)
            .animation(Fx.Motion.select, value: model.profileIsEmpty)
        }
        .scrollDismissesKeyboard(.interactively)
        .fxScreenBackground()
        .navigationTitle(Text("Profile"))
        .navigationBarTitleDisplayMode(.inline)
        .sensoryFeedback(.success, trigger: clears)
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
        } message: {
            Text("Your e-mail, name and phone are removed from this phone, and new reports won't ask for a reply. Reports you already sent keep them.")
        }
    }

    private var aboutRow: some View {
        Button {
            model.path.append(.about)
        } label: {
            FxCard {
                HStack(spacing: Fx.Space.m) {
                    Image(systemName: "info.circle")
                        .font(Fx.Font.headline)
                        .foregroundStyle(Fx.Color.sea)
                        .accessibilityHidden(true)
                    Text("About Fixa")
                        .font(Fx.Font.headline)
                        .foregroundStyle(Fx.Color.ink)
                    Spacer(minLength: Fx.Space.s)
                    Image(systemName: "chevron.forward")
                        .foregroundStyle(Fx.Color.ink2)
                        .accessibilityHidden(true)
                }
                .frame(minHeight: Fx.minTarget)
            }
        }
        .buttonStyle(FxPressStyle())
    }
}
