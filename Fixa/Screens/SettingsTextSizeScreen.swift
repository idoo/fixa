import FixaKit
import SwiftUI

/// "Use iPhone setting" or one of 8 steps up to AX3. The whole screen grows live; the Smaller /
/// Larger buttons sit in a bar fixed to the bottom so they never move under the finger.
struct SettingsTextSizeScreen: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        ScrollView {
            VStack(alignment: .leading, spacing: Fx.Space.l) {
                preview

                FxCard {
                    FxToggleRow(
                        title: String(localized: "Use iPhone setting"),
                        subtitle: String(localized: "Now: size \(systemStep.number) of \(TextSizeStep.allCases.count)"),
                        isOn: followsSystem
                    )
                }

                if let step = model.display.textSize {
                    Text("Size \(step.number) of \(TextSizeStep.allCases.count)")
                        .font(Fx.Font.headline)
                        .foregroundStyle(Fx.Color.ink)
                    FxProgressSteps(current: step.number, total: TextSizeStep.allCases.count)
                        .accessibilityHidden(true)
                }
            }
            .padding(Fx.Space.l)
        }
        .fxScreenBackground()
        .navigationTitle(Text("Text size"))
        .navigationBarTitleDisplayMode(.inline)
        .fxBottomBar {
            if let step = model.display.textSize {
                HStack(spacing: Fx.Space.m) {
                    FxSecondaryButton(title: String(localized: "Smaller text"), systemImage: "textformat.size.smaller") {
                        model.display.textSize = step.smaller ?? step
                    }
                    .disabled(step.smaller == nil)
                    FxSecondaryButton(title: String(localized: "Larger text"), systemImage: "textformat.size.larger") {
                        model.display.textSize = step.larger ?? step
                    }
                    .disabled(step.larger == nil)
                }
                .frame(minHeight: 56)
                // The buttons stay usable at any size: their text is capped so the bar keeps its place.
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            }
        }
    }

    /// The real screen at the chosen size: a Home tile and its subtitle.
    private var preview: some View {
        VStack(alignment: .leading, spacing: Fx.Space.m) {
            Text("Preview")
                .font(Fx.Font.footnote)
                .foregroundStyle(Fx.Color.ink2)
            Text("Report a problem in Värmdö in a minute.")
                .font(Fx.Font.body)
                .foregroundStyle(Fx.Color.ink)
                .fixedSize(horizontal: false, vertical: true)
            FxTile(title: String(localized: "Street light out"), systemImage: "lightbulb.slash", index: 2) {}
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    /// The iPhone's own text size, mapped to the nearest step.
    private var systemStep: TextSizeStep {
        let size = DynamicTypeSize(UIApplication.shared.preferredContentSizeCategory) ?? .large
        return TextSizeStep(nearest: size)
    }

    private var followsSystem: Binding<Bool> {
        Binding(
            get: { model.display.textSize == nil },
            set: { follows in
                model.display.textSize = follows ? nil : systemStep
            }
        )
    }
}
