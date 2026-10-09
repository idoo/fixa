import SwiftUI

/// Serif section title with optional supporting line.
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
                    .foregroundStyle(Fx.Color.inkSoft)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// Labelled switch row, whole row toggles.
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
                    .font(Fx.Font.body)
                    .foregroundStyle(Fx.Color.ink)
                if let subtitle {
                    Text(subtitle)
                        .font(Fx.Font.footnote)
                        .foregroundStyle(Fx.Color.inkSoft)
                }
            }
        }
        .tint(Fx.Color.accent)
        .frame(minHeight: Fx.minTarget)
        .sensoryFeedback(.selection, trigger: isOn)
    }
}

/// Calm inline message: info (sea), warning, error (Falu red), success (moss).
struct FxBanner: View {
    enum Kind: Sendable {
        case info, warning, error, success
    }

    let kind: Kind
    let title: String
    var message: String? = nil
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

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
                .font(Fx.Font.headline)
                .foregroundStyle(tone)
                .frame(minWidth: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Fx.Space.xs) {
                Text(title)
                    .font(Fx.Font.headline)
                    .foregroundStyle(Fx.Color.ink)
                if let message {
                    Text(message)
                        .font(Fx.Font.callout)
                        .foregroundStyle(Fx.Color.inkSoft)
                }
                if let actionTitle, let action {
                    Button(action: action) {
                        Text(actionTitle)
                            .font(Fx.Font.callout.weight(.semibold))
                            .foregroundStyle(tone)
                            .frame(minHeight: Fx.minTarget, alignment: .leading)
                            .contentShape(.rect)
                    }
                    .buttonStyle(FxPressStyle())
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Fx.Space.l)
        .background(tone.opacity(0.10), in: .rect(cornerRadius: Fx.Radius.m, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Fx.Radius.m, style: .continuous)
                .strokeBorder(tone.opacity(0.35), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
    }

    private var tone: Color {
        switch kind {
        case .info: Fx.Color.sea
        case .warning: Fx.Color.warn
        case .error: Fx.Color.accent
        case .success: Fx.Color.moss
        }
    }

    private var symbol: String {
        switch kind {
        case .info: "info.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .error: "xmark.octagon.fill"
        case .success: "checkmark.circle.fill"
        }
    }
}

/// Compact single-row phone shortcut (e.g. an emergency line): phone glyph, short title,
/// one secondary line (name and number) and a trailing call circle. The whole row is the
/// tap target; light impact haptic on tap. Put the number in `detail` only, so it shows once.
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
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Fx.Color.ink)
                    Text(detail)
                        .font(Fx.Font.footnote)
                        .foregroundStyle(Fx.Color.inkSoft)
                }
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                Image(systemName: "phone.arrow.up.right.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Fx.Color.onAccent)
                    .frame(width: callSide, height: callSide)
                    .background(Fx.Color.warn, in: .circle)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, Fx.Space.m)
            .padding(.vertical, Fx.Space.s)
            .frame(minHeight: Fx.minTarget + Fx.Space.s)
            .background(Fx.Color.warn.opacity(0.10), in: .rect(cornerRadius: Fx.Radius.m, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Fx.Radius.m, style: .continuous)
                    .strokeBorder(Fx.Color.warn.opacity(0.35), lineWidth: 1)
            }
            .contentShape(.rect(cornerRadius: Fx.Radius.m, style: .continuous))
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
            .buttonStyle(FxPressStyle())
        } else {
            content
                .accessibilityElement(children: .combine)
        }
    }

    private var content: some View {
        HStack(alignment: .firstTextBaseline, spacing: Fx.Space.m) {
            Image(systemName: systemImage)
                .font(Fx.Font.body)
                .foregroundStyle(Fx.Color.sea)
                .frame(width: iconColumn)
                .accessibilityHidden(true)
            Text(text)
                .font(link == nil ? Fx.Font.body : Fx.Font.body.weight(.semibold))
                .foregroundStyle(link == nil ? Fx.Color.ink : Fx.Color.sea)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            if link != nil {
                Image(systemName: "arrow.up.forward")
                    .font(Fx.Font.footnote.weight(.semibold))
                    .foregroundStyle(Fx.Color.sea)
                    .accessibilityHidden(true)
            }
        }
        .frame(minHeight: Fx.minTarget)
    }
}

/// Segmented step indicator. `current` is 1-based.
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
                    .fill(step <= safeCurrent ? Fx.Color.accent : Fx.Color.line)
                    .frame(height: 4)
            }
        }
        .animation(Fx.Motion.select, value: safeCurrent)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(String(localized: "Progress", comment: "Accessibility label for the step indicator")))
        .accessibilityValue(Text(String(localized: "Step \(safeCurrent) of \(safeTotal)", comment: "Accessibility value for the step indicator")))
    }
}
