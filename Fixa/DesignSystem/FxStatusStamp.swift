import SwiftUI
import UIKit

/// The one brand accent: a cone-orange receipt stamp. Ink type on cone (5.54:1), simple double border,
/// "MOTTAGET" + monospaced case number, rotated −6°, and a one-shot "stamp" landing (spring + success haptic).
/// Reduce Motion: appears in place without the landing. Accessibility text sizes: capped at AX1, upright,
/// and allowed to shrink to the width (the case number also appears as plain text on the receipt).
struct FxStatusStamp: View {
    let caseNumber: String?

    @Environment(\.fxReduceMotion) private var reduceMotion
    @Environment(\.fxHaptics) private var haptics
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var stamped = false

    init(caseNumber: String?) {
        self.caseNumber = caseNumber
    }

    var body: some View {
        stamp
            .rotationEffect(.degrees(dynamicTypeSize.isAccessibilitySize ? 0 : -6))
            .scaleEffect(stamped || reduceMotion ? 1 : 1.4)
            .opacity(stamped || reduceMotion ? 1 : 0)
            .padding(Fx.Space.l)
            .sensoryFeedback(.success, trigger: stamped) { _, _ in haptics }
            .onAppear {
                guard !stamped else { return }
                if reduceMotion {
                    stamped = true
                } else {
                    withAnimation(.spring(response: 0.38, dampingFraction: 0.55).delay(0.15)) {
                        stamped = true
                    }
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(accessibilityText))
            .accessibilityAddTraits(.isStaticText)
    }

    private var stamp: some View {
        let shape = RoundedRectangle(cornerRadius: Fx.Radius.s, style: .continuous)
        return VStack(spacing: Fx.Space.xs) {
            Text(verbatim: "MOTTAGET")
                .font(Fx.Font.stamp)
                .tracking(4)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(verbatim: caseNumber.map { "Nr \($0)" } ?? "Fixa")
                .font(Fx.Font.stampNumber)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .foregroundStyle(Fx.Color.onCone)
        .padding(.horizontal, Fx.Space.xl)
        .padding(.vertical, Fx.Space.l)
        .background(Fx.Color.cone, in: shape)
        .overlay {
            RoundedRectangle(cornerRadius: Fx.Radius.s - 4, style: .continuous)
                .strokeBorder(Fx.Color.onCone, lineWidth: Fx.Border.hairline)
                .padding(Fx.Space.xs + 2)
        }
        .overlay(shape.strokeBorder(Fx.Color.onCone, lineWidth: Fx.Border.emphasis))
        .fixedSize(horizontal: false, vertical: true)
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
    }

    private var accessibilityText: String {
        if let caseNumber {
            String(localized: "Received. Case number \(caseNumber)", comment: "Accessibility label of the receipt stamp")
        } else {
            String(localized: "Received", comment: "Accessibility label of the receipt stamp without case number")
        }
    }
}

/// Compact bordered copy control that sits under the stamp (case number) or a fallback text.
/// Copies `value` to the pasteboard, plays a success haptic, shows `copiedTitle` for 1.5 s and announces it.
struct FxCopyButton: View {
    let title: String
    let copiedTitle: String
    let value: String

    @State private var copies = 0
    @State private var copied = false
    @Environment(\.fxHaptics) private var haptics
    @Environment(\.fxReduceMotion) private var reduceMotion

    init(title: String, copiedTitle: String = String(localized: "Copied"), value: String) {
        self.title = title
        self.copiedTitle = copiedTitle
        self.value = value
    }

    var body: some View {
        Button {
            UIPasteboard.general.string = value
            copies += 1
            copied = true
            AccessibilityNotification.Announcement(copiedTitle).post()
        } label: {
            HStack(spacing: Fx.Space.s) {
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    .imageScale(.medium)
                    .contentTransition(.symbolEffect(.replace))
                    .accessibilityHidden(true)
                Text(copied ? copiedTitle : title)
                    .font(Fx.Font.callout.weight(.semibold))
                    .multilineTextAlignment(.center)
            }
            .foregroundStyle(copied ? Fx.Color.success : Fx.Color.sea)
            .padding(.horizontal, Fx.Space.l)
            .padding(.vertical, Fx.Space.s)
            .frame(minHeight: Fx.minTarget)
            .fxOutline(RoundedRectangle(cornerRadius: Fx.Radius.m, style: .continuous))
            .contentShape(.rect(cornerRadius: Fx.Radius.m, style: .continuous))
            .animation(reduceMotion ? nil : Fx.Motion.select, value: copied)
        }
        .buttonStyle(FxPressStyle())
        .sensoryFeedback(.success, trigger: copies) { _, _ in haptics }
        .task(id: copies) {
            guard copied else { return }
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            copied = false
        }
        .accessibilityLabel(Text(copied ? copiedTitle : title))
    }
}
