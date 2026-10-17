import SwiftUI

/// Heavy rounded section title with optional supporting line.
struct FxSectionHeader: View {
    let title: String
    var subtitle: String? = nil

    init(_ title: String, subtitle: String? = nil) {
        self.title = title
        self.subtitle = subtitle
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Fx.Space.xs) {
            Text(title)
                .font(Fx.Font.title)
                .foregroundStyle(Fx.Color.ink)
                .accessibilityAddTraits(.isHeader)
            if let subtitle {
                Text(subtitle)
                    .font(Fx.Font.callout)
                    .foregroundStyle(Fx.Color.ink2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// Dashed 2 pt rule between rows inside an `FxCard`, quieter than the card's ink outline.
struct FxDivider: View {
    var body: some View {
        Rule()
            .stroke(Fx.Color.ink2.opacity(0.45), style: StrokeStyle(lineWidth: Fx.Sticker.line, lineCap: .round, dash: [6, 6]))
            .frame(height: Fx.Sticker.line)
            .accessibilityHidden(true)
    }

    private struct Rule: Shape {
        nonisolated func path(in rect: CGRect) -> Path {
            var path = Path()
            path.move(to: CGPoint(x: rect.minX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
            return path
        }
    }
}

/// Labelled switch row, whole row toggles. Sea switch.
struct FxToggleRow: View {
    let title: String
    var subtitle: String? = nil
    @Binding var isOn: Bool

    init(title: String, subtitle: String? = nil, isOn: Binding<Bool>) {
        self.title = title
        self.subtitle = subtitle
        self._isOn = isOn
    }

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: Fx.Space.xs) {
                Text(title)
                    .font(Fx.Font.headline)
                    .foregroundStyle(Fx.Color.ink)
                if let subtitle {
                    Text(subtitle)
                        .font(Fx.Font.footnote)
                        .foregroundStyle(Fx.Color.ink2)
                }
            }
        }
        .tint(Fx.Color.sea)
        .frame(minHeight: Fx.minTarget)
        .sensoryFeedback(.selection, trigger: isOn)
    }
}

/// Pastel sticker message: info (sky), warning (sun), error (rose), success (mint). Ink text on the
/// pastel in both appearances; the kind's glyph sits in a small badge.
struct FxBanner: View {
    enum Kind: Sendable {
        case info, warning, error, success
    }

    let kind: Kind
    let title: String
    var message: String? = nil
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    @ScaledMetric(relativeTo: .headline) private var badgeSide: CGFloat = 30

    init(kind: Kind, title: String, message: String? = nil, actionTitle: String? = nil, action: (() -> Void)? = nil) {
        self.kind = kind
        self.title = title
        self.message = message
        self.actionTitle = actionTitle
        self.action = action
    }

    var body: some View {
        HStack(alignment: .top, spacing: Fx.Space.m) {
            Image(systemName: symbol)
                .font(Fx.Font.subheadline.weight(.black))
                .foregroundStyle(Fx.Color.onPastel)
                .frame(width: badgeSide, height: badgeSide)
                .fxOutline(Circle(), fill: .clear, outline: Fx.Color.onPastel)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Fx.Space.xs) {
                Text(title)
                    .font(Fx.Font.headline)
                    .foregroundStyle(Fx.Color.onPastel)
                if let message {
                    Text(message)
                        .font(Fx.Font.callout)
                        .foregroundStyle(Fx.Color.onPastel2)
                }
                if let actionTitle, let action {
                    Button(action: action) {
                        Text(actionTitle)
                            .font(Fx.Font.callout.weight(.bold))
                            .underline()
                            .foregroundStyle(Fx.Color.onPastel)
                            .frame(minHeight: Fx.minTarget, alignment: .leading)
                            .contentShape(.rect)
                    }
                    .buttonStyle(FxPressStyle(dims: true))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Fx.Space.l)
        .fxSticker(
            RoundedRectangle(cornerRadius: Fx.Radius.l, style: .continuous),
            fill: fill,
            depth: Fx.Sticker.depth - 1,
            pressable: false
        )
        .accessibilityElement(children: .combine)
    }

    private var fill: Color {
        switch kind {
        case .info: Fx.Color.Pastel.sky
        case .warning: Fx.Color.Pastel.sun
        case .error: Fx.Color.Pastel.rose
        case .success: Fx.Color.Pastel.mint
        }
    }

    private var symbol: String {
        switch kind {
        case .info: "info"
        case .warning: "exclamationmark"
        case .error: "xmark"
        case .success: "checkmark"
        }
    }
}

/// Compact single-row phone shortcut (e.g. an emergency line): short title, one secondary line
/// (number and name) and a trailing cone call badge, on a sun-pastel sticker. The whole row is the
/// tap target and sinks when pressed; light impact haptic on tap. Put the number in `detail` only, so it shows once.
struct FxCallRow: View {
    let title: String
    let detail: String
    let action: () -> Void

    @State private var taps = 0
    @ScaledMetric(relativeTo: .subheadline) private var callSide: CGFloat = 36

    init(title: String, detail: String, action: @escaping () -> Void) {
        self.title = title
        self.detail = detail
        self.action = action
    }

    var body: some View {
        Button {
            taps += 1
            action()
        } label: {
            HStack(spacing: Fx.Space.m) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(Fx.Font.subheadline.weight(.bold))
                        .foregroundStyle(Fx.Color.onPastel)
                    Text(detail)
                        .font(Fx.Font.footnote)
                        .foregroundStyle(Fx.Color.onPastel2)
                }
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                Image(systemName: "phone.arrow.up.right.fill")
                    .font(Fx.Font.subheadline.weight(.heavy))
                    .foregroundStyle(Fx.Color.onCone)
                    .frame(width: callSide, height: callSide)
                    .fxSticker(Circle(), fill: Fx.Color.cone, depth: Fx.Sticker.smallDepth, pressable: false)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, Fx.Space.m)
            .padding(.vertical, Fx.Space.s)
            .frame(minHeight: Fx.minTarget + Fx.Space.s)
            .fxSticker(
                RoundedRectangle(cornerRadius: Fx.Radius.m, style: .continuous),
                fill: Fx.Color.Pastel.sun
            )
        }
        .buttonStyle(FxPressStyle())
        .sensoryFeedback(.impact(weight: .light), trigger: taps)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(title))
        .accessibilityValue(Text(detail))
        .accessibilityHint(Text(String(localized: "Starts a phone call", comment: "Accessibility hint for a call row")))
        .accessibilityAddTraits(.isButton)
    }
}

/// Short leading-icon line for lists inside an `FxCard` (e.g. About's facts).
/// Pass `link` to make the whole row open a URL (sea text, trailing arrow).
struct FxIconRow: View {
    let systemImage: String
    let text: String
    var link: URL? = nil
    /// Fixed icon column so every row's text starts on one leading edge, whatever the glyph width.
    @ScaledMetric(relativeTo: .body) private var iconColumn: CGFloat = 28

    init(systemImage: String, text: String, link: URL? = nil) {
        self.systemImage = systemImage
        self.text = text
        self.link = link
    }

    var body: some View {
        if let link {
            Link(destination: link) {
                content
                    .contentShape(.rect)
            }
            .buttonStyle(FxPressStyle(dims: true))
        } else {
            content
                .accessibilityElement(children: .combine)
        }
    }

    private var content: some View {
        HStack(alignment: .firstTextBaseline, spacing: Fx.Space.m) {
            Image(systemName: systemImage)
                .font(Fx.Font.body.weight(.bold))
                .foregroundStyle(Fx.Color.sea)
                .frame(width: iconColumn)
                .accessibilityHidden(true)
            Text(text)
                .font(link == nil ? Fx.Font.body : Fx.Font.body.weight(.bold))
                .foregroundStyle(link == nil ? Fx.Color.ink : Fx.Color.sea)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            if link != nil {
                Image(systemName: "arrow.up.forward")
                    .font(Fx.Font.footnote.weight(.heavy))
                    .foregroundStyle(Fx.Color.sea)
                    .accessibilityHidden(true)
            }
        }
        .frame(minHeight: Fx.minTarget)
    }
}

/// Segmented step indicator: outlined capsules, done steps filled cone. `current` is 1-based.
struct FxProgressSteps: View {
    let current: Int
    let total: Int

    init(current: Int, total: Int) {
        self.current = current
        self.total = total
    }

    private var safeTotal: Int { max(total, 1) }
    private var safeCurrent: Int { min(max(current, 0), safeTotal) }

    var body: some View {
        HStack(spacing: Fx.Space.xs) {
            ForEach(1...safeTotal, id: \.self) { step in
                Capsule()
                    .fill(step <= safeCurrent ? Fx.Color.cone : Fx.Color.card)
                    .overlay(Capsule().strokeBorder(Fx.Color.line, lineWidth: Fx.Sticker.line))
                    .frame(height: 10)
            }
        }
        .animation(Fx.Motion.select, value: safeCurrent)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(String(localized: "Progress", comment: "Accessibility label for the step indicator")))
        .accessibilityValue(Text(String(localized: "Step \(safeCurrent) of \(safeTotal)", comment: "Accessibility value for the step indicator")))
    }
}
