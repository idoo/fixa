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

    /// Hex convenience: `Color(light: 0xF7F5F0, dark: 0x121A22)`.
    init(light: UInt32, dark: UInt32) {
        self.init(light: UIColor(fxHex: light), dark: UIColor(fxHex: dark))
    }

    /// One colour in both appearances (the brand stamp, ink on pastel fills).
    init(fxHex hex: UInt32) {
        self.init(uiColor: UIColor(fxHex: hex))
    }
}

// MARK: - Tokens

/// Fixa design system namespace. Screens use only these tokens and the `Fx*` components.
enum Fx {
    /// Calm civic palette: warm off-white paper, white cards, hairline borders, one sea-blue action colour.
    /// WCAG (sRGB): ink on paper 14.5 / 12+ dark; ink2 ≥ 5.8 light / ≥ 7.3 dark; sea text 6.7 on paper,
    /// 8.3 on dark card; white on `action` 7.27 light (#1F5A8A) / 5.36 dark (#2E6FA3).
    enum Color {
        /// Screen background.
        static let paper = SwiftUI.Color(light: 0xF7F5F0, dark: 0x121A22)
        /// Cards, fields, tiles.
        static let card = SwiftUI.Color(light: 0xFFFFFF, dark: 0x1B2530)
        /// Primary text.
        static let ink = SwiftUI.Color(light: 0x1E2136, dark: 0xF3EAD6)
        /// Secondary text, icons at rest.
        static let ink2 = SwiftUI.Color(light: 0x5B5F73, dark: 0xB9B2A2)
        /// Hairline borders and rules (1 pt).
        static let line = SwiftUI.Color(light: 0xD8D2C6, dark: 0x33414F)
        /// Sea blue for text: links, selected, focus, map pins, switches.
        static let sea = SwiftUI.Color(light: 0x1F5A8A, dark: 0x8CC4F0)
        /// Primary action fill (sea), with `onAction` text.
        static let action = SwiftUI.Color(light: 0x1F5A8A, dark: 0x2E6FA3)
        /// Text and glyphs on `action`.
        static let onAction = SwiftUI.Color(fxHex: 0xFFFFFF)
        /// Brand accent, traffic-cone orange. Receipt stamp only.
        static let cone = SwiftUI.Color(fxHex: 0xFF6A2B)
        /// Text on `cone` (5.54:1).
        static let onCone = SwiftUI.Color(fxHex: 0x1E2136)
        /// Glyphs on pastel fills, both appearances (≥ 10.7:1).
        static let onPastel = SwiftUI.Color(fxHex: 0x1E2136)
        /// Errors and validation.
        static let error = SwiftUI.Color(light: 0xB3261E, dark: 0xFF8A80)
        /// Success.
        static let success = SwiftUI.Color(light: 0x3E7D4F, dark: 0x8FCB9C)
        /// Warning sun: accent bars only, never text.
        static let warning = SwiftUI.Color(fxHex: 0xF2B233)
        /// Very soft card shadow in light mode (black 6 %); none at night.
        static let shadow = SwiftUI.Color(light: UIColor(fxHex: 0x000000, alpha: 0.06), dark: .clear)

        /// Muted pastels (≈ 20 % desaturated) for small icon circles; same in both appearances.
        enum Pastel {
            static let mint = SwiftUI.Color(fxHex: 0xC3E4D2)
            static let sky = SwiftUI.Color(fxHex: 0xCDE2F2)
            static let sun = SwiftUI.Color(fxHex: 0xF3DA96)
            static let peach = SwiftUI.Color(fxHex: 0xF8D2BC)
            static let lilac = SwiftUI.Color(fxHex: 0xDDD3F1)
            static let sand = SwiftUI.Color(fxHex: 0xE6DAC4)
            static let rose = SwiftUI.Color(fxHex: 0xF2CBD2)
            static let foam = SwiftUI.Color(fxHex: 0xD2ECE8)
        }

        /// Tile order: neighbours in a 2-column grid never share a pastel.
        static let pastels: [SwiftUI.Color] = [
            Pastel.mint, Pastel.sky, Pastel.sun, Pastel.peach,
            Pastel.lilac, Pastel.sand, Pastel.rose, Pastel.foam,
        ]

        /// Deterministic pastel for the n-th item of a list.
        static func pastel(at index: Int) -> SwiftUI.Color {
            pastels[((index % pastels.count) + pastels.count) % pastels.count]
        }
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
        /// Fields, photos, maps.
        static let s: CGFloat = 10
        /// Cards, tiles, buttons.
        static let m: CGFloat = 12
    }

    /// Border widths: hairline at rest, emphasis for focus, selection and errors.
    enum Border {
        static let hairline: CGFloat = 1
        static let emphasis: CGFloat = 2
    }

    /// Dynamic-Type text styles, SF Pro.
    enum Font {
        static let largeTitle = SwiftUI.Font.system(.largeTitle, weight: .bold)
        static let title = SwiftUI.Font.system(.title2, weight: .semibold)
        static let title3 = SwiftUI.Font.system(.title3, weight: .semibold)
        static let headline = SwiftUI.Font.system(.headline, weight: .semibold)
        static let subheadline = SwiftUI.Font.system(.subheadline, weight: .semibold)
        static let body = SwiftUI.Font.system(.body)
        static let callout = SwiftUI.Font.system(.callout)
        static let footnote = SwiftUI.Font.system(.footnote)
        /// "MOTTAGET" on the receipt stamp.
        static let stamp = SwiftUI.Font.system(.title, weight: .heavy)
        /// Case number on the stamp.
        static let stampNumber = SwiftUI.Font.system(.headline, design: .monospaced, weight: .semibold)
    }

    enum Motion {
        static let press = Animation.easeOut(duration: 0.12)
        static let select = Animation.spring(response: 0.35, dampingFraction: 0.85)
    }

    /// Minimum hit target (HIG).
    static let minTarget: CGFloat = 44
}

// MARK: - Pressed state

/// Shared pressed state: a quick opacity dip. Nothing moves, so it is the same with Reduce Motion.
struct FxPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.65 : 1)
            .animation(Fx.Motion.press, value: configuration.isPressed)
    }
}

// MARK: - Surfaces

extension View {
    /// Card surface: `fill`, 1 pt hairline border, and the very soft light-mode shadow.
    func fxCardSurface<S: InsettableShape>(
        _ shape: S,
        fill: SwiftUI.Color = Fx.Color.card,
        border: SwiftUI.Color = Fx.Color.line,
        borderWidth: CGFloat = Fx.Border.hairline
    ) -> some View {
        background {
            shape.fill(fill)
                .shadow(color: Fx.Color.shadow, radius: 3, y: 1)
        }
        .overlay(shape.strokeBorder(border, lineWidth: borderWidth))
    }

    /// Flat bordered surface without shadow (fields, photos, maps, inset slots).
    func fxOutline<S: InsettableShape>(
        _ shape: S,
        fill: SwiftUI.Color = Fx.Color.card,
        outline: SwiftUI.Color = Fx.Color.line,
        width: CGFloat = Fx.Border.hairline
    ) -> some View {
        background(fill, in: shape)
            .overlay(shape.strokeBorder(outline, lineWidth: width))
    }
}

// MARK: - Screen background

private struct FxScreenBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .scrollContentBackground(.hidden)
            .background(Fx.Color.paper.ignoresSafeArea())
            .foregroundStyle(Fx.Color.ink)
            .tint(Fx.Color.sea)
    }
}

extension View {
    /// Paper screen background, ink text, sea tint for system controls and links.
    func fxScreenBackground() -> some View {
        modifier(FxScreenBackground())
    }
}
