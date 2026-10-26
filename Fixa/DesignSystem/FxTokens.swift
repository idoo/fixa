import SwiftUI
import UIKit

// MARK: - Light/dark colour helper

extension UIColor {
    /// `0xRRGGBB` → sRGB colour.
    convenience init(fxHex hex: UInt32, alpha: CGFloat = 1) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }
}

extension SwiftUI.Color {
    /// A colour that resolves per trait collection (light / dark), backed by a dynamic `UIColor`.
    /// The provider is `nonisolated`: SwiftUI resolves colours on its async render thread
    /// (e.g. while a ProgressView animates), and a MainActor-isolated closure traps there.
    nonisolated init(light: UIColor, dark: UIColor) {
        let provider: @Sendable (UITraitCollection) -> UIColor = { traits in
            traits.userInterfaceStyle == .dark ? dark : light
        }
        self.init(uiColor: UIColor(dynamicProvider: provider))
    }

    /// Hex convenience: `Color(light: 0xF6F2EA, dark: 0x16191C)`.
    init(light: UInt32, dark: UInt32) {
        self.init(light: UIColor(fxHex: light), dark: UIColor(fxHex: dark))
    }
}

// MARK: - Tokens

/// Fixa design system namespace. Screens use only these tokens and the `Fx*` components.
enum Fx {
    /// Scandinavian palette: birch paper, ink, one saturated accent (Falu red).
    enum Color {
        /// Birch off-white screen background.
        static let paper = SwiftUI.Color(light: 0xF6F2EA, dark: 0x16191C)
        /// Raised surfaces (cards, fields, tiles).
        static let card = SwiftUI.Color(light: 0xFFFFFF, dark: 0x20252A)
        /// Primary text.
        static let ink = SwiftUI.Color(light: 0x1C2630, dark: 0xECE8E1)
        /// Secondary text, icons at rest.
        static let inkSoft = SwiftUI.Color(light: 0x5E6B75, dark: 0xA9B3BA)
        /// Falu red. The ONE saturated accent per screen.
        static let accent = SwiftUI.Color(light: 0xA8322D, dark: 0xE0675F)
        /// Muted archipelago blue, secondary/informational.
        static let sea = SwiftUI.Color(light: 0x3D6378, dark: 0x8DB4C9)
        /// Success.
        static let moss = SwiftUI.Color(light: 0x4F7A43, dark: 0x8DBB7F)
        /// Warning.
        static let warn = SwiftUI.Color(light: 0xB7791F, dark: 0xE3B15A)
        /// Hairlines, borders.
        static let line = SwiftUI.Color(light: 0xE4DDD1, dark: 0x2E353B)
        /// Text/icon colour on top of `accent` fills.
        static let onAccent = SwiftUI.Color(light: 0xFFFFFF, dark: 0x16191C)
    }

    /// 4/8 pt spacing scale.
    enum Space {
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 16
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
        static let xxxl: CGFloat = 48
    }

    enum Radius {
        static let s: CGFloat = 10
        static let m: CGFloat = 16
        static let l: CGFloat = 24
    }

    /// Dynamic-Type text styles. Titles: New York (serif) semibold. Body: SF Pro.
    enum Font {
        static let largeTitle = SwiftUI.Font.system(.largeTitle, design: .serif, weight: .semibold)
        static let title = SwiftUI.Font.system(.title2, design: .serif, weight: .semibold)
        static let headline = SwiftUI.Font.system(.headline, design: .default, weight: .semibold)
        static let body = SwiftUI.Font.system(.body)
        static let callout = SwiftUI.Font.system(.callout)
        static let footnote = SwiftUI.Font.system(.footnote)
    }

    enum Motion {
        static let press = Animation.spring(response: 0.25, dampingFraction: 0.7)
        static let select = Animation.spring(response: 0.35, dampingFraction: 0.8)
    }

    /// Minimum hit target (HIG).
    static let minTarget: CGFloat = 44
}

// MARK: - Pressed state

/// Shared pressed state: scale 0.97 with a spring. Respects Reduce Motion (opacity dip instead).
struct FxPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .opacity(configuration.isPressed && reduceMotion ? 0.8 : 1)
            .animation(Fx.Motion.press, value: configuration.isPressed)
    }
}

// MARK: - Screen background

private struct FxScreenBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .scrollContentBackground(.hidden)
            .background(Fx.Color.paper.ignoresSafeArea())
            .foregroundStyle(Fx.Color.ink)
            .tint(Fx.Color.accent)
    }
}

extension View {
    /// Paper (birch off-white) screen background, ink text, Falu-red tint.
    func fxScreenBackground() -> some View {
        modifier(FxScreenBackground())
    }
}
