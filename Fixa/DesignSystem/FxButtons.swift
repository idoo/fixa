import SwiftUI

/// Filled sea-blue call to action with white text. One per screen. Impact haptic on tap.
/// White on fill: 7.27:1 light (#1F5A8A), 5.36:1 dark (#2E6FA3). Disabled by the caller: faded.
struct FxPrimaryButton: View {
    let title: String
    var systemImage: String? = nil
    var isLoading: Bool = false
    let action: () -> Void

    @State private var taps = 0
    @Environment(\.fxHaptics) private var haptics
    @Environment(\.isEnabled) private var isEnabled

    init(title: String, systemImage: String? = nil, isLoading: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.isLoading = isLoading
        self.action = action
    }

    var body: some View {
        Button {
            guard !isLoading else { return }
            taps += 1
            action()
        } label: {
            HStack(spacing: Fx.Space.s) {
                if isLoading {
                    ProgressView()
                        .tint(Fx.Color.onAction)
                        .accessibilityHidden(true)
                } else if let systemImage {
                    Image(systemName: systemImage)
                        .imageScale(.medium)
                        .accessibilityHidden(true)
                }
                Text(title)
                    .font(Fx.Font.headline)
                    .multilineTextAlignment(.center)
            }
            .foregroundStyle(Fx.Color.onAction)
            .frame(maxWidth: .infinity, minHeight: 50)
            .padding(.horizontal, Fx.Space.l)
            .padding(.vertical, Fx.Space.xs)
            .background(Fx.Color.action, in: .rect(cornerRadius: Fx.Radius.m, style: .continuous))
            .opacity(isEnabled ? 1 : 0.45)
            .contentShape(.rect(cornerRadius: Fx.Radius.m, style: .continuous))
        }
        .buttonStyle(FxPressStyle())
        .disabled(isLoading)
        .sensoryFeedback(.impact(weight: .medium), trigger: taps) { _, _ in haptics }
        .accessibilityLabel(Text(title))
        .accessibilityValue(isLoading ? Text(String(localized: "Loading…", comment: "Accessibility value on a busy button")) : Text(""))
    }
}

/// Quiet companion button: card fill, hairline border, sea text.
struct FxSecondaryButton: View {
    let title: String
    var systemImage: String? = nil
    let action: () -> Void

    @State private var taps = 0
    @Environment(\.fxHaptics) private var haptics

    init(title: String, systemImage: String? = nil, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.action = action
    }

    var body: some View {
        Button {
            taps += 1
            action()
        } label: {
            FxSecondaryLabel(title: title, systemImage: systemImage)
        }
        .buttonStyle(FxPressStyle())
        .sensoryFeedback(.impact(weight: .light), trigger: taps) { _, _ in haptics }
        .accessibilityLabel(Text(title))
    }
}

/// The look of `FxSecondaryButton`, for controls that bring their own action (e.g. `PhotosPicker`).
/// Pair with `.buttonStyle(FxPressStyle())`.
struct FxSecondaryLabel: View {
    let title: String
    var systemImage: String? = nil

    var body: some View {
        HStack(spacing: Fx.Space.s) {
            if let systemImage {
                Image(systemName: systemImage)
                    .imageScale(.medium)
                    .accessibilityHidden(true)
            }
            Text(title)
                .font(Fx.Font.headline)
                .multilineTextAlignment(.center)
        }
        .foregroundStyle(Fx.Color.sea)
        .frame(maxWidth: .infinity, minHeight: 50)
        .padding(.horizontal, Fx.Space.l)
        .padding(.vertical, Fx.Space.xs)
        .fxOutline(RoundedRectangle(cornerRadius: Fx.Radius.m, style: .continuous))
        .contentShape(.rect(cornerRadius: Fx.Radius.m, style: .continuous))
    }
}

/// Round icon-only control, e.g. floating over a map. `label` is read by VoiceOver.
struct FxIconButton: View {
    let systemImage: String
    let label: String
    var isLoading: Bool = false
    let action: () -> Void

    @State private var taps = 0
    @Environment(\.fxHaptics) private var haptics
    @ScaledMetric(relativeTo: .headline) private var scaledSide: CGFloat = 48
    /// Grows with Dynamic Type, capped so it never covers the content it floats over.
    private var side: CGFloat { min(scaledSide, 88) }

    init(systemImage: String, label: String, isLoading: Bool = false, action: @escaping () -> Void) {
        self.systemImage = systemImage
        self.label = label
        self.isLoading = isLoading
        self.action = action
    }

    var body: some View {
        Button {
            guard !isLoading else { return }
            taps += 1
            action()
        } label: {
            ZStack {
                if isLoading {
                    ProgressView()
                        .tint(Fx.Color.sea)
                } else {
                    Image(systemName: systemImage)
                        .font(Fx.Font.headline)
                        .foregroundStyle(Fx.Color.sea)
                }
            }
            .frame(width: side, height: side)
            .fxCardSurface(Circle())
            .contentShape(Circle())
        }
        .buttonStyle(FxPressStyle())
        .sensoryFeedback(.impact(weight: .light), trigger: taps) { _, _ in haptics }
        .accessibilityLabel(Text(label))
        .accessibilityShowsLargeContentViewer()
    }
}

/// White surface for grouping content: radius 12, hairline border, very soft light-mode shadow.
struct FxCard<Content: View>: View {
    @ViewBuilder let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Fx.Space.m) {
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Fx.Space.l)
        .fxCardSurface(RoundedRectangle(cornerRadius: Fx.Radius.m, style: .continuous))
    }
}

/// Small muted pastel circle with an ink glyph. Decorative.
struct FxBadge: View {
    let systemImage: String
    var fill: Color
    var side: CGFloat

    init(systemImage: String, fill: Color, side: CGFloat) {
        self.systemImage = systemImage
        self.fill = fill
        self.side = side
    }

    var body: some View {
        Image(systemName: systemImage)
            .font(Fx.Font.body)
            .imageScale(side >= 56 ? .large : .medium)
            .foregroundStyle(Fx.Color.onPastel)
            .frame(width: side, height: side)
            .background(fill, in: Circle())
            .accessibilityHidden(true)
    }
}

/// Compact category tile for a 2-column grid: white card, muted pastel glyph circle above a semibold
/// title, both on one leading edge. `index` picks the pastel so the grid is varied but stable. The title
/// never truncates; LazyVGrid gives each row its tallest tile's height. Selected: 2 pt sea border. Selection haptic.
struct FxTile: View {
    let title: String
    let systemImage: String
    var index: Int = 0
    var isSelected: Bool = false
    let action: () -> Void

    @State private var taps = 0
    @Environment(\.fxHaptics) private var haptics
    @Environment(\.fxReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .body) private var iconSide: CGFloat = 36

    init(title: String, systemImage: String, index: Int = 0, isSelected: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.index = index
        self.isSelected = isSelected
        self.action = action
    }

    var body: some View {
        Button {
            taps += 1
            action()
        } label: {
            VStack(alignment: .leading, spacing: Fx.Space.s) {
                FxBadge(systemImage: systemImage, fill: Fx.Color.pastel(at: index), side: iconSide)
                titleText
            }
            .padding(Fx.Space.m)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .fxCardSurface(
                RoundedRectangle(cornerRadius: Fx.Radius.m, style: .continuous),
                border: isSelected ? Fx.Color.sea : Fx.Color.line,
                borderWidth: isSelected ? Fx.Border.emphasis : Fx.Border.hairline
            )
            .contentShape(.rect(cornerRadius: Fx.Radius.m, style: .continuous))
            .animation(reduceMotion ? nil : Fx.Motion.select, value: isSelected)
        }
        .buttonStyle(FxPressStyle())
        .sensoryFeedback(.selection, trigger: taps) { _, _ in haptics }
        .accessibilityLabel(Text(title))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var titleText: some View {
        Text(title)
            .font(Fx.Font.headline)
            .foregroundStyle(Fx.Color.ink)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
    }
}
