import SwiftUI
import UIKit

/// Signature element: a Falu-red rubber stamp on the receipt.
/// Double rounded border, dashed inner rule, "MOTTAGET" + case number, rotated −6°,
/// faint ink speckle, and a one-shot "stamp" landing (spring + success haptic).
/// Reduce Motion: appears in place without the landing.
struct FxStatusStamp: View {
    let caseNumber: String?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var stamped = false

    init(caseNumber: String?) {
        self.caseNumber = caseNumber
    }

    var body: some View {
        stamp
            .rotationEffect(.degrees(-6))
            .scaleEffect(stamped || reduceMotion ? 1 : 1.4)
            .opacity(stamped || reduceMotion ? 1 : 0)
            .padding(Fx.Space.l)
            .sensoryFeedback(.success, trigger: stamped)
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
        VStack(spacing: Fx.Space.xs) {
            Text(verbatim: "MOTTAGET")
                .font(.system(.title, design: .default, weight: .black))
                .tracking(5)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Rectangle()
                .frame(height: 1.5)
                .padding(.horizontal, Fx.Space.s)
            Text(verbatim: caseNumber.map { "Nr \($0)" } ?? "Fixa")
                .font(.system(.headline, design: .monospaced, weight: .bold))
                .monospacedDigit()
                .tracking(1.5)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .padding(.horizontal, Fx.Space.xl)
        .padding(.vertical, Fx.Space.l)
        .overlay {
            RoundedRectangle(cornerRadius: Fx.Radius.s, style: .continuous)
                .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 3]))
                .padding(Fx.Space.xs + 2)
        }
        .overlay {
            RoundedRectangle(cornerRadius: Fx.Radius.s + 4, style: .continuous)
                .strokeBorder(lineWidth: 3.5)
        }
        .foregroundStyle(Fx.Color.accent)
        .mask { FxInkTexture() }
        .opacity(0.92)
        .fixedSize()
    }

    private var accessibilityText: String {
        if let caseNumber {
            String(localized: "Received. Case number \(caseNumber)", comment: "Accessibility label of the receipt stamp")
        } else {
            String(localized: "Received", comment: "Accessibility label of the receipt stamp without case number")
        }
    }
}

/// Compact copy control that sits under the stamp (case number) or a fallback text.
/// Copies `value` to the pasteboard, plays a success haptic, and shows `copiedTitle` for 1.5 s.
struct FxCopyButton: View {
    let title: String
    let copiedTitle: String
    let value: String

    @State private var copies = 0
    @State private var copied = false

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
            .foregroundStyle(copied ? Fx.Color.moss : Fx.Color.ink)
            .padding(.horizontal, Fx.Space.l)
            .padding(.vertical, Fx.Space.s)
            .frame(minHeight: Fx.minTarget)
            .background(Fx.Color.card, in: Capsule())
            .overlay(Capsule().strokeBorder(Fx.Color.line, lineWidth: 1))
            .contentShape(Capsule())
            .animation(Fx.Motion.select, value: copied)
        }
        .buttonStyle(FxPressStyle())
        .sensoryFeedback(.success, trigger: copies)
        .task(id: copies) {
            guard copied else { return }
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            copied = false
        }
        .accessibilityLabel(Text(copied ? copiedTitle : title))
    }
}

/// Deterministic ink speckle used as a mask: mostly opaque, with small worn-out flecks.
private struct FxInkTexture: View {
    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.white))
            var seed: UInt64 = 0x9E3779B97F4A7C15
            func next() -> CGFloat {
                seed = seed &* 6364136223846793005 &+ 1442695040888963407
                return CGFloat((seed >> 33) & 0xFFFF) / CGFloat(0xFFFF)
            }
            let count = Int(size.width * size.height / 70)
            context.blendMode = .destinationOut
            for _ in 0..<count {
                let x = next() * size.width
                let y = next() * size.height
                let r = 0.4 + next() * 1.3
                let alpha = 0.25 + next() * 0.6
                context.fill(
                    Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)),
                    with: .color(.white.opacity(alpha))
                )
            }
        }
        .accessibilityHidden(true)
    }
}
