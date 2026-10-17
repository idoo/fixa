import SwiftUI

/// Cone-orange sticker call to action. One per screen. Impact haptic on tap.
/// Ink text on cone (5.54:1). Disabled by the caller: flat card with secondary text, no shadow.
struct FxPrimaryButton: View {
    let title: String
    var systemImage: String? = nil
    var isLoading: Bool = false
    let action: () -> Void

    @State private var taps = 0
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
                        .tint(Fx.Color.onCone)
                        .accessibilityHidden(true)
                } else if let systemImage {
                    Image(systemName: systemImage)
                        .imageScale(.medium)
                        .fontWeight(.heavy)
                        .accessibilityHidden(true)
                }
                Text(title)
                    .font(Fx.Font.headline)
                    .multilineTextAlignment(.center)
            }
            .foregroundStyle(isEnabled ? Fx.Color.onCone : Fx.Color.ink2)
            .frame(maxWidth: .infinity, minHeight: 52)
            .padding(.horizontal, Fx.Space.l)
            .padding(.vertical, Fx.Space.xs)
            .fxSticker(
                RoundedRectangle(cornerRadius: Fx.Radius.m, style: .continuous),
                fill: isEnabled ? Fx.Color.cone : Fx.Color.card,
                depth: isEnabled ? Fx.Sticker.depth : 0
            )
            .padding(.top, isEnabled ? 0 : Fx.Sticker.depth)
        }
        .buttonStyle(FxPressStyle())
        .disabled(isLoading)
        .sensoryFeedback(.impact(weight: .medium), trigger: taps)
        .accessibilityLabel(Text(title))
        .accessibilityValue(isLoading ? Text(String(localized: "Loading…", comment: "Accessibility value on a busy button")) : Text(""))
    }
}

/// Card-coloured sticker companion button.
struct FxSecondaryButton: View {
    let title: String
    var systemImage: String? = nil
    let action: () -> Void

    @State private var taps = 0

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
        .sensoryFeedback(.impact(weight: .light), trigger: taps)
        .accessibilityLabel(Text(title))
    }
}

/// The look of `FxSecondaryButton`, for controls that bring their own action (e.g. `PhotosPicker`).
/// Pair with `.buttonStyle(FxPressStyle())` so it sinks when pressed.
struct FxSecondaryLabel: View {
    let title: String
    var systemImage: String? = nil

    var body: some View {
        HStack(spacing: Fx.Space.s) {
            if let systemImage {
                Image(systemName: systemImage)
                    .imageScale(.medium)
                    .fontWeight(.bold)
                    .accessibilityHidden(true)
            }
            Text(title)
                .font(Fx.Font.headline)
                .multilineTextAlignment(.center)
        }
        .foregroundStyle(Fx.Color.ink)
        .frame(maxWidth: .infinity, minHeight: 48)
        .padding(.horizontal, Fx.Space.l)
        .padding(.vertical, Fx.Space.xs)
        .fxSticker(RoundedRectangle(cornerRadius: Fx.Radius.m, style: .continuous))
    }
}

/// Round sticker icon-only control, e.g. floating over a map. `label` is read by VoiceOver.
struct FxIconButton: View {
    let systemImage: String
    let label: String
    var isLoading: Bool = false
    let action: () -> Void

    @State private var taps = 0

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
                        .tint(Fx.Color.ink)
                } else {
                    Image(systemName: systemImage)
                        .font(Fx.Font.headline)
                        .fontWeight(.heavy)
                        .foregroundStyle(Fx.Color.ink)
                }
            }
            .frame(width: 48, height: 48)
            .fxSticker(Circle(), depth: Fx.Sticker.depth - 1)
        }
        .buttonStyle(FxPressStyle())
        .sensoryFeedback(.impact(weight: .light), trigger: taps)
        .accessibilityLabel(Text(label))
    }
}

/// Raised sticker surface for grouping content. Inside an `FxPressStyle` button it sinks when pressed.
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
        .fxSticker(RoundedRectangle(cornerRadius: Fx.Radius.l, style: .continuous))
    }
}

/// Pastel circle badge with an ink glyph, outline and a small hard shadow. Decorative.
/// Stays still while a surrounding sticker button sinks.
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
            .font(Fx.Font.title3)
            .foregroundStyle(Fx.Color.onPastel)
            .frame(width: side, height: side)
            .fxSticker(Circle(), fill: fill, depth: Fx.Sticker.smallDepth, pressable: false)
            .accessibilityHidden(true)
    }
}

/// Compact category tile for a 2-column grid: pastel badge above a title of up to two lines, both on one
/// leading edge. `index` picks the badge pastel so the grid is varied but stable. The title reserves two
/// lines so sibling tiles share one height; at accessibility sizes it grows instead of truncating.
/// Selected: the whole tile takes its pastel. Selection haptic.
struct FxTile: View {
    let title: String
    let systemImage: String
    var index: Int = 0
    var isSelected: Bool = false
    let action: () -> Void

    @State private var taps = 0
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .title3) private var iconSide: CGFloat = 44

    init(title: String, systemImage: String, index: Int = 0, isSelected: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.index = index
        self.isSelected = isSelected
        self.action = action
    }

    var body: some View {
        let pastel = Fx.Color.pastel(at: index)
        Button {
            taps += 1
            action()
        } label: {
            VStack(alignment: .leading, spacing: Fx.Space.m) {
                FxBadge(systemImage: systemImage, fill: pastel, side: iconSide)
                titleText
            }
            .padding(Fx.Space.m)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .fxSticker(
                RoundedRectangle(cornerRadius: Fx.Radius.l, style: .continuous),
                fill: isSelected ? pastel : Fx.Color.card
            )
            .animation(Fx.Motion.select, value: isSelected)
        }
        .buttonStyle(FxPressStyle())
        .sensoryFeedback(.selection, trigger: taps)
        .accessibilityLabel(Text(title))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    @ViewBuilder private var titleText: some View {
        let text = Text(title)
            .font(Fx.Font.headline)
            .foregroundStyle(isSelected ? Fx.Color.onPastel : Fx.Color.ink)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        if dynamicTypeSize.isAccessibilitySize {
            text.fixedSize(horizontal: false, vertical: true)
        } else {
            text.lineLimit(2, reservesSpace: true)
        }
    }
}
