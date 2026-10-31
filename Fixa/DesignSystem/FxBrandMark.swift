import SwiftUI

/// The icon's two traffic cones on a strip of jetty, drawn from shapes (no raster). Brand moments only:
/// onboarding, empty states. Decorative: hidden from VoiceOver. Cones are `cone` orange with a navy outline
/// in both appearances, as on the app icon.
struct FxBrandMark: View {
    var size: CGFloat = 72

    private static let outline = Color(fxHex: 0x1E2136)
    private static let stripe = Color(fxHex: 0xFFF6EA)

    var body: some View {
        let line = max(1.5, size * 0.035)
        ZStack(alignment: .bottom) {
            HStack(alignment: .bottom, spacing: -size * 0.08) {
                cone(height: size * 0.92, line: line)
                cone(height: size * 0.7, line: line)
            }
            .padding(.bottom, size * 0.07)
            Capsule()
                .fill(Fx.Color.sea)
                .frame(width: size * 1.25, height: size * 0.1)
        }
        .frame(width: size * 1.3, height: size)
        .accessibilityHidden(true)
    }

    private func cone(height: CGFloat, line: CGFloat) -> some View {
        let width = height * 0.72
        return VStack(spacing: -line) {
            ZStack {
                FxConeShape()
                    .fill(Fx.Color.cone)
                FxConeStripe()
                    .fill(Self.stripe)
                FxConeShape()
                    .stroke(Self.outline, style: StrokeStyle(lineWidth: line, lineJoin: .round))
            }
            .frame(width: width * 0.78, height: height * 0.86)
            RoundedRectangle(cornerRadius: height * 0.04, style: .continuous)
                .fill(Fx.Color.cone)
                .overlay(
                    RoundedRectangle(cornerRadius: height * 0.04, style: .continuous)
                        .stroke(Self.outline, lineWidth: line)
                )
                .frame(width: width, height: height * 0.14)
        }
    }
}

/// Cone body: a trapezoid with a rounded top.
private struct FxConeShape: Shape {
    nonisolated func path(in rect: CGRect) -> Path {
        let top = rect.width * 0.16
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.midX - top, y: rect.minY + top))
        p.addQuadCurve(
            to: CGPoint(x: rect.midX + top, y: rect.minY + top),
            control: CGPoint(x: rect.midX, y: rect.minY - top * 0.6)
        )
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

/// The reflective band across the middle of the cone body.
private struct FxConeStripe: Shape {
    nonisolated func path(in rect: CGRect) -> Path {
        let top = rect.width * 0.16
        func x(atY y: CGFloat, leading: Bool) -> CGFloat {
            // Linear edge from (midX ∓ top, minY + top) to (minX/maxX, maxY).
            let t = (y - (rect.minY + top)) / (rect.maxY - (rect.minY + top))
            let start = leading ? rect.midX - top : rect.midX + top
            let end = leading ? rect.minX : rect.maxX
            return start + (end - start) * t
        }
        let y0 = rect.minY + rect.height * 0.42
        let y1 = rect.minY + rect.height * 0.62
        var p = Path()
        p.move(to: CGPoint(x: x(atY: y0, leading: true), y: y0))
        p.addLine(to: CGPoint(x: x(atY: y0, leading: false), y: y0))
        p.addLine(to: CGPoint(x: x(atY: y1, leading: false), y: y1))
        p.addLine(to: CGPoint(x: x(atY: y1, leading: true), y: y1))
        p.closeSubpath()
        return p
    }
}

/// Empty state: the brand mark, a short title, an optional one-line message and an optional action
/// (e.g. an `FxSecondaryButton`). Centred; strings come in localized.
struct FxEmptyState<Action: View>: View {
    let title: String
    var message: String?
    private let action: Action

    init(title: String, message: String? = nil, @ViewBuilder action: () -> Action = { EmptyView() }) {
        self.title = title
        self.message = message
        self.action = action()
    }

    var body: some View {
        VStack(spacing: Fx.Space.l) {
            FxBrandMark(size: 64)
            VStack(spacing: Fx.Space.xs) {
                Text(title)
                    .font(Fx.Font.title3)
                    .foregroundStyle(Fx.Color.ink)
                    .accessibilityAddTraits(.isHeader)
                if let message {
                    Text(message)
                        .font(Fx.Font.callout)
                        .foregroundStyle(Fx.Color.ink2)
                }
            }
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            action
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Fx.Space.xl)
    }
}
