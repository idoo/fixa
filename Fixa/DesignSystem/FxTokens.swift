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

    /// Hex convenience: `Color(light: 0xFFF4DD, dark: 0x15202B)`.
    init(light: UInt32, dark: UInt32) {
        self.init(light: UIColor(fxHex: light), dark: UIColor(fxHex: dark))
    }

    /// One colour in both appearances (art fills that stay light at night, ink on those fills).
    init(fxHex hex: UInt32) {
        self.init(uiColor: UIColor(fxHex: hex))
    }
}

// MARK: - Tokens

/// Fixa design system namespace. Screens use only these tokens and the `Fx*` components.
enum Fx {
    /// "Skärgård & vägarbete": cream paper, ink, archipelago sea, traffic-cone orange, flat pastels.
    /// WCAG (sRGB): ink on paper 14.5 (dark 12.0 on card); ink2 ≥ 5.8 light / ≥ 6.8 dark;
    /// sea 6.7 on paper / 7.7 on dark card; onCone on cone 5.54 (white would be 2.86, fails).
    enum Color {
        /// Cream screen background; navy night.
        static let paper = SwiftUI.Color(light: 0xFFF4DD, dark: 0x15202B)
        /// Raised surfaces (cards, fields, tiles).
        static let card = SwiftUI.Color(light: 0xFFFFFF, dark: 0x1E2B38)
        /// Primary text.
        static let ink = SwiftUI.Color(light: 0x1E2136, dark: 0xF3EAD6)
        /// Secondary text, icons at rest.
        static let ink2 = SwiftUI.Color(light: 0x5B5F73, dark: 0xB9B2A2)
        /// Archipelago blue: links, info, map pin, selected, switches.
        static let sea = SwiftUI.Color(light: 0x1F5A8A, dark: 0x8CC4F0)
        /// Traffic-cone orange: THE action fill (primary button, stamp). Fill only, never text.
        static let cone = SwiftUI.Color(fxHex: 0xFF6A2B)
        /// Text and glyphs on `cone`: ink in both appearances (5.54:1).
        static let onCone = SwiftUI.Color(fxHex: 0x1E2136)
        /// Text and glyphs on pastel / warning fills, both appearances (≥ 10.5:1).
        static let onPastel = SwiftUI.Color(fxHex: 0x1E2136)
        /// Secondary text on pastel fills (≥ 5.4:1 on every pastel).
        static let onPastel2 = SwiftUI.Color(fxHex: 0x4A4E61)
        /// Stuga red: errors and validation.
        static let error = SwiftUI.Color(light: 0xB3261E, dark: 0xFF8A80)
        /// Moss: success.
        static let success = SwiftUI.Color(light: 0x3E7D4F, dark: 0x8FCB9C)
        /// Sun: warning fill (text on it is `onPastel`).
        static let warning = SwiftUI.Color(fxHex: 0xF2B233)
        /// Sticker outline: ink by day, a soft slate at night (≥ 5:1 on dark surfaces).
        static let line = SwiftUI.Color(light: 0x1E2136, dark: 0x8E9BA8)
        /// Hard, unblurred drop shadow under raised stickers.
        static let shadow = SwiftUI.Color(light: 0x1E2136, dark: 0x05090E)

        /// Flat pastel fills for badges and tiles; light in both appearances, ink on top.
        enum Pastel {
            static let mint = SwiftUI.Color(fxHex: 0xBFE8D2)
            static let sky = SwiftUI.Color(fxHex: 0xC9E3F6)
            static let sun = SwiftUI.Color(fxHex: 0xFFE08A)
            static let peach = SwiftUI.Color(fxHex: 0xFFD0B5)
            static let lilac = SwiftUI.Color(fxHex: 0xDCCFF5)
            static let sand = SwiftUI.Color(fxHex: 0xEADBC0)
            static let rose = SwiftUI.Color(fxHex: 0xF7C6CF)
            static let foam = SwiftUI.Color(fxHex: 0xCFEFEA)
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
        static let s: CGFloat = 12
        static let m: CGFloat = 18
        static let l: CGFloat = 24
    }

    /// Sticker metrics: 2 pt ink outline, hard shadow straight down (no blur).
    enum Sticker {
        static let line: CGFloat = 2
        /// Raised surfaces: cards, buttons, tiles.
        static let depth: CGFloat = 4
        /// Small controls: chips, icon buttons, badges.
        static let smallDepth: CGFloat = 2
    }

    /// Dynamic-Type text styles. Titles: SF Rounded heavy/black. Body: SF Rounded.
    enum Font {
        static let largeTitle = SwiftUI.Font.system(.largeTitle, design: .rounded, weight: .black)
        static let title = SwiftUI.Font.system(.title2, design: .rounded, weight: .heavy)
        static let title3 = SwiftUI.Font.system(.title3, design: .rounded, weight: .heavy)
        static let headline = SwiftUI.Font.system(.headline, design: .rounded, weight: .bold)
        static let subheadline = SwiftUI.Font.system(.subheadline, design: .rounded, weight: .semibold)
        static let body = SwiftUI.Font.system(.body, design: .rounded)
        static let callout = SwiftUI.Font.system(.callout, design: .rounded)
        static let footnote = SwiftUI.Font.system(.footnote, design: .rounded)
        /// "MOTTAGET" on the receipt stamp.
        static let stamp = SwiftUI.Font.system(.title, design: .rounded, weight: .black)
        /// Case number on the stamp.
        static let stampNumber = SwiftUI.Font.system(.headline, design: .monospaced, weight: .bold)
    }

    enum Motion {
        static let press = Animation.spring(response: 0.25, dampingFraction: 0.6)
        static let select = Animation.spring(response: 0.35, dampingFraction: 0.8)
    }

    /// Minimum hit target (HIG).
    static let minTarget: CGFloat = 44
}

// MARK: - Pressed state

extension EnvironmentValues {
    /// True while the enclosing `FxPressStyle` button is held; sticker surfaces sink into their shadow.
    @Entry var fxPressed: Bool = false
}

/// Shared pressed state. Passes the press to `fxSticker` surfaces in the label, which sink into
/// their hard shadow. `dims` gives labels without a sticker (rows, links) an opacity dip instead.
struct FxPressStyle: ButtonStyle {
    var dims: Bool = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .environment(\.fxPressed, configuration.isPressed)
            .opacity(dims && configuration.isPressed ? 0.6 : 1)
            .animation(reduceMotion ? nil : Fx.Motion.press, value: configuration.isPressed)
    }
}

// MARK: - Sticker surfaces

/// Fill, 2 pt outline and a hard offset shadow straight down. While an `FxPressStyle` button is held
/// the face drops onto its shadow; Reduce Motion dips opacity instead of moving.
private struct FxSticker<S: InsettableShape>: ViewModifier {
    let shape: S
    let fill: SwiftUI.Color
    let outline: SwiftUI.Color
    let depth: CGFloat
    let pressable: Bool

    @Environment(\.fxPressed) private var pressed
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        let isPressed = pressable && pressed
        content
            .background(fill, in: shape)
            .overlay(shape.strokeBorder(outline, lineWidth: Fx.Sticker.line))
            .offset(y: isPressed && !reduceMotion ? depth : 0)
            .background {
                if depth > 0 {
                    shape.fill(Fx.Color.shadow).offset(y: depth)
                }
            }
            .opacity(isPressed && reduceMotion ? 0.75 : 1)
            .padding(.bottom, depth)
            .contentShape(shape)
    }
}

extension View {
    /// Raised sticker: `fill`, ink outline, hard ink shadow `depth` pt below.
    /// `pressable: false` keeps nested decorations (badges) still while the surrounding button sinks.
    func fxSticker<S: InsettableShape>(
        _ shape: S,
        fill: SwiftUI.Color = Fx.Color.card,
        outline: SwiftUI.Color = Fx.Color.line,
        depth: CGFloat = Fx.Sticker.depth,
        pressable: Bool = true
    ) -> some View {
        modifier(FxSticker(shape: shape, fill: fill, outline: outline, depth: depth, pressable: pressable))
    }

    /// Flat outlined surface without a shadow (fields, photos, inset slots).
    func fxOutline<S: InsettableShape>(
        _ shape: S,
        fill: SwiftUI.Color = Fx.Color.card,
        outline: SwiftUI.Color = Fx.Color.line
    ) -> some View {
        background(fill, in: shape)
            .overlay(shape.strokeBorder(outline, lineWidth: Fx.Sticker.line))
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
    /// Cream paper screen background, ink text, sea tint for system controls and links.
    func fxScreenBackground() -> some View {
        modifier(FxScreenBackground())
    }
}
