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
        .accessibilityValue(isLoading ? Text(String(localized: "Loading…", bundle: L10n.bundle, locale: L10n.locale, comment: "Accessibility value on a busy button")) : Text(""))
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

/// Category tile for `FxTileGrid`: white card, muted pastel glyph circle centred at the top, a centred
/// semibold title in the space below. `index` picks the pastel so the grid is varied but stable. The title
/// never truncates and reserves at least two lines; the grid gives every tile the tallest tile's height, so
/// icons share one line per row and shorter titles centre in the leftover space. Selected: 2 pt sea border.
/// Selection haptic.
struct FxTile: View {
    let title: String
    let systemImage: String
    var index: Int = 0
    var isSelected: Bool = false
    let action: () -> Void

    @State private var taps = 0
    @Environment(\.fxHaptics) private var haptics
    @Environment(\.fxReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .body) private var iconSide: CGFloat = 44

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
            VStack(spacing: Fx.Space.s) {
                FxBadge(systemImage: systemImage, fill: Fx.Color.pastel(at: index), side: iconSide)
                titleText
            }
            .padding(.horizontal, Fx.Space.m)
            .padding(.vertical, Fx.Space.l)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
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

    /// Centred title over a hidden two-line placeholder: grows past two lines, never shrinks below them, and
    /// centres in whatever height the grid gives the tile.
    private var titleText: some View {
        ZStack {
            Text(verbatim: " \n ")
                .hidden()
                .accessibilityHidden(true)
            Text(title)
                .foregroundStyle(Fx.Color.ink)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(Fx.Font.headline)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Grid for `FxTile`s: every cell gets the tallest cell's height across all rows, so a three-line title in
/// one row doesn't make that row taller than the rest. Cells are placed leading to trailing; SwiftUI
/// mirrors the placement in right-to-left languages.
struct FxTileGrid: Layout {
    var columns: Int
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.replacingUnspecifiedDimensions().width
        let rows = (subviews.count + columns - 1) / columns
        guard rows > 0 else { return CGSize(width: width, height: 0) }
        let height = cellHeight(subviews, width: cellWidth(width))
        return CGSize(width: width, height: height * CGFloat(rows) + spacing * CGFloat(rows - 1))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let width = cellWidth(bounds.width)
        let height = cellHeight(subviews, width: width)
        for (index, subview) in subviews.enumerated() {
            let origin = CGPoint(
                x: bounds.minX + CGFloat(index % columns) * (width + spacing),
                y: bounds.minY + CGFloat(index / columns) * (height + spacing)
            )
            subview.place(at: origin, proposal: ProposedViewSize(width: width, height: height))
        }
    }

    private func cellWidth(_ width: CGFloat) -> CGFloat {
        max(0, (width - spacing * CGFloat(columns - 1)) / CGFloat(columns))
    }

    private func cellHeight(_ subviews: Subviews, width: CGFloat) -> CGFloat {
        subviews.map { $0.sizeThatFits(ProposedViewSize(width: width, height: nil)).height }.max() ?? 0
    }
}
