import SwiftUI
import UIKit

/// Signature element: a traffic-cone orange rubber-stamp sticker on the receipt.
/// Cone face with ink type (5.54:1), ink outline, dashed inner rule, worn ink speckle, hard shadow,
/// "MOTTAGET" + case number, rotated −6°, and a one-shot "stamp" landing (spring + success haptic).
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
        let shape = RoundedRectangle(cornerRadius: Fx.Radius.m, style: .continuous)
        return VStack(spacing: Fx.Space.xs) {
            Text(verbatim: "MOTTAGET")
                .font(Fx.Font.stamp)
                .tracking(5)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Rectangle()
                .frame(height: Fx.Sticker.line)
                .padding(.horizontal, Fx.Space.s)
            Text(verbatim: caseNumber.map { "Nr \($0)" } ?? "Fixa")
                .font(Fx.Font.stampNumber)
                .monospacedDigit()
                .tracking(1.5)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .foregroundStyle(Fx.Color.onCone)
        .padding(.horizontal, Fx.Space.xl)
        .padding(.vertical, Fx.Space.l)
        .overlay {
            RoundedRectangle(cornerRadius: Fx.Radius.s, style: .continuous)
                .strokeBorder(Fx.Color.onCone, style: StrokeStyle(lineWidth: 1.5, dash: [6, 3]))
                .padding(Fx.Space.xs + 2)
        }
        .background(Fx.Color.cone, in: shape)
        .overlay(shape.strokeBorder(Fx.Color.onCone, lineWidth: Fx.Sticker.line + 1))
        .mask { FxInkTexture() }
        .background(shape.fill(Fx.Color.shadow).offset(y: Fx.Sticker.depth + 1))
        .padding(.bottom, Fx.Sticker.depth + 1)
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

/// Compact sticker-capsule copy control that sits under the stamp (case number) or a fallback text.
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
                    .fontWeight(.bold)
                    .contentTransition(.symbolEffect(.replace))
                    .accessibilityHidden(true)
                Text(copied ? copiedTitle : title)
                    .font(Fx.Font.callout.weight(.bold))
                    .multilineTextAlignment(.center)
            }
            .foregroundStyle(copied ? Fx.Color.success : Fx.Color.ink)
            .padding(.horizontal, Fx.Space.l)
            .padding(.vertical, Fx.Space.s)
            .frame(minHeight: Fx.minTarget)
            .fxSticker(Capsule(), depth: Fx.Sticker.depth - 1)
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
/// Only alpha matters in a mask; `Fx.Color.ink` is just an opaque paint.
private struct FxInkTexture: View {
    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Fx.Color.ink))
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
                    with: .color(Fx.Color.ink.opacity(alpha))
                )
            }
        }
        .accessibilityHidden(true)
    }
}
