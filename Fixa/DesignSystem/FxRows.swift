import SwiftUI

/// Semibold section title with optional supporting line.
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

/// Small group label above a card (settings groups, history sections): footnote semibold ink2.
/// The one section-label style; use `FxSectionHeader` only for a screen's own title block.
struct FxGroupHeader: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(Fx.Font.section)
            .foregroundStyle(Fx.Color.ink2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Fx.Space.xs)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
    }
}

/// 1 pt hairline between rows inside an `FxCard`.
struct FxDivider: View {
    var body: some View {
        Rectangle()
            .fill(Fx.Color.line)
            .frame(height: Fx.Border.hairline)
            .accessibilityHidden(true)
    }
}

/// Labelled switch row, whole row toggles. Sea switch.
struct FxToggleRow: View {
    let title: String
    var subtitle: String? = nil
    @Binding var isOn: Bool
    @Environment(\.fxHaptics) private var haptics

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
                        .foregroundStyle(Fx.Color.ink2)
                }
            }
        }
        .tint(Fx.Color.sea)
        .frame(minHeight: Fx.minTarget)
        .sensoryFeedback(.selection, trigger: isOn) { _, _ in haptics }
    }
}

/// Calm inline message: white card with a 4 pt leading bar in the kind's colour
/// (info sea, warning sun, error red, success green) and a matching glyph.
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
                .foregroundStyle(glyphTone)
                .frame(minWidth: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Fx.Space.xs) {
                Text(title)
                    .font(Fx.Font.headline)
                    .foregroundStyle(Fx.Color.ink)
                if let message {
                    Text(message)
                        .font(Fx.Font.callout)
                        .foregroundStyle(Fx.Color.ink2)
                }
                if let actionTitle, let action {
                    Button(action: action) {
                        Text(actionTitle)
                            .font(Fx.Font.callout.weight(.semibold))
                            .underline()
                            .foregroundStyle(Fx.Color.sea)
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
        .padding(.leading, Fx.Space.xs)
        .fxAccentBar(barTone)
        .accessibilityElement(children: .combine)
    }

    /// Bar colour; decorative, so the warning sun may be light.
    private var barTone: Color {
        switch kind {
        case .info: Fx.Color.sea
        case .warning: Fx.Color.warning
        case .error: Fx.Color.error
        case .success: Fx.Color.success
        }
    }

    /// Glyph colour; the warning glyph stays ink because sun on white is too faint.
    private var glyphTone: Color {
        switch kind {
        case .info: Fx.Color.sea
        case .warning: Fx.Color.ink
        case .error: Fx.Color.error
        case .success: Fx.Color.success
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

extension View {
    /// Card surface with a 4 pt coloured bar on the leading edge (mirrors in RTL).
    fileprivate func fxAccentBar(_ tone: Color) -> some View {
        let shape = RoundedRectangle(cornerRadius: Fx.Radius.m, style: .continuous)
        return frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .leading) {
                Rectangle().fill(tone).frame(width: 4)
            }
            .clipShape(shape)
            .fxCardSurface(shape)
    }
}

/// Compact single-row phone shortcut (e.g. an emergency line): white card with a warning-sun leading
/// bar, short title, one secondary line (number and name) and a trailing sea call circle. The whole row
/// is the tap target; light impact haptic on tap. Put the number in `detail` only, so it shows once, and
/// wrap it in `ltrIsolated` so it keeps its order in Arabic. `accessibilityValue` (default `detail`) is what
/// VoiceOver reads after the title: pass the raw number and name. `inputLabels` are Voice Control names.
struct FxCallRow: View {
    let title: String
    let detail: String
    let accessibilityValue: String?
    let inputLabels: [String]
    let action: () -> Void

    @State private var taps = 0
    @Environment(\.fxHaptics) private var haptics
    @ScaledMetric(relativeTo: .subheadline) private var callSide: CGFloat = 36

    init(
        title: String,
        detail: String,
        accessibilityValue: String? = nil,
        inputLabels: [String] = [],
        action: @escaping () -> Void
    ) {
        self.title = title
        self.detail = detail
        self.accessibilityValue = accessibilityValue
        self.inputLabels = inputLabels
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
                        .font(Fx.Font.subheadline)
                        .foregroundStyle(Fx.Color.ink)
                    Text(detail)
                        .font(Fx.Font.footnote)
                        .foregroundStyle(Fx.Color.ink2)
                }
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                Image(systemName: "phone.fill")
                    .font(Fx.Font.subheadline)
                    .foregroundStyle(Fx.Color.onAction)
                    .frame(width: callSide, height: callSide)
                    .background(Fx.Color.action, in: .circle)
                    .accessibilityHidden(true)
            }
            .padding(.leading, Fx.Space.m + Fx.Space.xs)
            .padding(.trailing, Fx.Space.m)
            .padding(.vertical, Fx.Space.s)
            .frame(minHeight: Fx.minTarget + Fx.Space.s)
            .fxAccentBar(Fx.Color.warning)
            .contentShape(.rect(cornerRadius: Fx.Radius.m, style: .continuous))
        }
        .buttonStyle(FxPressStyle())
        .sensoryFeedback(.impact(weight: .light), trigger: taps) { _, _ in haptics }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(title))
        .accessibilityValue(Text(accessibilityValue ?? detail))
        .accessibilityInputLabels(([String(localized: "Call", bundle: L10n.bundle, locale: L10n.locale, comment: "Voice Control name of a call row"), title] + inputLabels).map { Text($0) })
        .accessibilityHint(Text(String(localized: "Starts a phone call", bundle: L10n.bundle, locale: L10n.locale, comment: "Accessibility hint for a call row")))
        .accessibilityAddTraits(.isButton)
    }
}

/// Short leading-icon line for lists inside an `FxCard` (e.g. About's facts).
/// Pass `link` to make the whole row open a URL, or `action` to make it a button (sea text, trailing arrow).
struct FxIconRow: View {
    let systemImage: String
    let text: String
    var link: URL? = nil
    var action: (() -> Void)? = nil
    /// Fixed icon column so every row's text starts on one leading edge, whatever the glyph width.
    @ScaledMetric(relativeTo: .body) private var iconColumn: CGFloat = 28

    init(systemImage: String, text: String, link: URL? = nil) {
        self.systemImage = systemImage
        self.text = text
        self.link = link
    }

    init(systemImage: String, text: String, action: @escaping () -> Void) {
        self.systemImage = systemImage
        self.text = text
        self.action = action
    }

    private var isTappable: Bool { link != nil || action != nil }

    var body: some View {
        if let link {
            Link(destination: link) {
                content
                    .contentShape(.rect)
            }
            .buttonStyle(FxPressStyle())
        } else if let action {
            Button(action: action) {
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
                .font(isTappable ? Fx.Font.body.weight(.semibold) : Fx.Font.body)
                .foregroundStyle(isTappable ? Fx.Color.sea : Fx.Color.ink)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            if isTappable {
                Image(systemName: "arrow.up.forward")
                    .font(Fx.Font.footnote.weight(.semibold))
                    .foregroundStyle(Fx.Color.sea)
                    .accessibilityHidden(true)
            }
        }
        .frame(minHeight: Fx.minTarget)
    }
}

/// Segmented step indicator: done steps sea, the rest hairline grey. `current` is 1-based.
struct FxProgressSteps: View {
    let current: Int
    let total: Int
    @Environment(\.fxReduceMotion) private var reduceMotion

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
                    .fill(step <= safeCurrent ? Fx.Color.sea : Fx.Color.fieldBorder)
                    .frame(height: 4)
            }
        }
        .animation(reduceMotion ? nil : Fx.Motion.select, value: safeCurrent)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(String(localized: "Progress", bundle: L10n.bundle, locale: L10n.locale, comment: "Accessibility label for the step indicator")))
        .accessibilityValue(Text(String(localized: "Step \(safeCurrent) of \(safeTotal)", bundle: L10n.bundle, locale: L10n.locale, comment: "Accessibility value for the step indicator")))
    }
}

extension String {
    /// Wrapped in Unicode left-to-right isolates (U+2066 … U+2069) so phone numbers and codes keep their
    /// order inside right-to-left text (Arabic). Neutral characters like "+" and "‑" otherwise flip.
    var ltrIsolated: String { "\u{2066}\(self)\u{2069}" }
}
