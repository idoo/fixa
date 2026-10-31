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

    /// Light / dark plus Increase Contrast variants (`traits.accessibilityContrast == .high`),
    /// which the iPhone setting and the in-app "Higher contrast" toggle both turn on.
    nonisolated init(light: UIColor, dark: UIColor, hcLight: UIColor, hcDark: UIColor) {
        let provider: @Sendable (UITraitCollection) -> UIColor = { traits in
            let high = traits.accessibilityContrast == .high
            if traits.userInterfaceStyle == .dark {
                return high ? hcDark : dark
            }
            return high ? hcLight : light
        }
        self.init(uiColor: UIColor(dynamicProvider: provider))
    }

    /// Hex convenience: `Color(light: 0xF7F5F0, dark: 0x121A22)`.
    init(light: UInt32, dark: UInt32) {
        self.init(light: UIColor(fxHex: light), dark: UIColor(fxHex: dark))
    }

    /// Hex convenience with Increase Contrast variants.
    init(light: UInt32, dark: UInt32, hcLight: UInt32, hcDark: UInt32) {
        self.init(
            light: UIColor(fxHex: light),
            dark: UIColor(fxHex: dark),
            hcLight: UIColor(fxHex: hcLight),
            hcDark: UIColor(fxHex: hcDark)
        )
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
        /// Secondary text, icons at rest. Increase Contrast: 9.0 light / 10.3 dark.
        static let ink2 = SwiftUI.Color(light: 0x5B5F73, dark: 0xB9B2A2, hcLight: 0x40434F, hcDark: 0xD9D2C2)
        /// Hairline borders and rules on cards (1 pt). Increase Contrast: the `fieldBorder` values.
        static let line = SwiftUI.Color(light: 0xD8D2C6, dark: 0x33414F, hcLight: 0x857F73, hcDark: 0x75879A)
        /// Resting border of inputs, chips and add slots (WCAG 1.4.11, ≥ 3:1 on card and paper).
        static let fieldBorder = SwiftUI.Color(light: 0x857F73, dark: 0x75879A, hcLight: 0x6B655A, hcDark: 0x93A4B5)
        /// Sea blue for text: links, selected, focus, map pins, switches.
        static let sea = SwiftUI.Color(light: 0x1F5A8A, dark: 0x8CC4F0)
        /// Primary action fill (sea), with `onAction` text. Increase Contrast dark: white on it 7.29.
        static let action = SwiftUI.Color(light: 0x1F5A8A, dark: 0x2E6FA3, hcLight: 0x1F5A8A, hcDark: 0x245A86)
        /// Text and glyphs on `action`.
        static let onAction = SwiftUI.Color(fxHex: 0xFFFFFF)
        /// Brand accent, traffic-cone orange. Receipt stamp only.
        static let cone = SwiftUI.Color(fxHex: 0xFF6A2B)
        /// Text on `cone` (5.54:1).
        static let onCone = SwiftUI.Color(fxHex: 0x1E2136)
        /// Ink glyph on light fills (`FxBadge` default), both appearances (≥ 10.7:1 on light fills).
        static let onPastel = SwiftUI.Color(fxHex: 0x1E2136)
        /// Errors and validation.
        static let error = SwiftUI.Color(light: 0xB3261E, dark: 0xFF8A80)
        /// Success.
        static let success = SwiftUI.Color(light: 0x3E7D4F, dark: 0x8FCB9C)
        /// Warning sun: accent bars only, never text.
        static let warning = SwiftUI.Color(fxHex: 0xF2B233)
        /// Very soft card shadow in light mode (black 6 %); none at night.
        static let shadow = SwiftUI.Color(light: UIColor(fxHex: 0x000000, alpha: 0.06), dark: .clear)

        /// Category fill with meaning per adapter category (`categories[].id`): lighting = sun,
        /// roads = asphalt/sand, graffiti = lilac, parks = mint, water = sky, other / nil / unknown = neutral sand.
        /// Pastel by day, deep tone at night; `categoryGlyph` on it is ≥ 5.0:1 light and ≥ 7.3:1 dark.
        static func categoryTint(_ categoryID: String?) -> SwiftUI.Color {
            categoryPair(categoryID).tint
        }

        /// Glyph (SF Symbol) colour on `categoryTint` of the same category.
        static func categoryGlyph(_ categoryID: String?) -> SwiftUI.Color {
            categoryPair(categoryID).glyph
        }

        private static func categoryPair(_ categoryID: String?) -> (tint: SwiftUI.Color, glyph: SwiftUI.Color) {
            switch categoryID {
            case "lighting": (CategoryTone.sunTint, CategoryTone.sunGlyph)
            case "roads": (CategoryTone.asphaltTint, CategoryTone.asphaltGlyph)
            case "graffiti": (CategoryTone.lilacTint, CategoryTone.lilacGlyph)
            case "parks": (CategoryTone.mintTint, CategoryTone.mintGlyph)
            case "water": (CategoryTone.skyTint, CategoryTone.skyGlyph)
            default: (CategoryTone.sandTint, CategoryTone.sandGlyph)
            }
        }

        /// Tint / glyph pairs (WCAG glyph on tint, light / dark): sun 6.3 / 7.8, asphalt 6.3 / 8.7,
        /// lilac 6.7 / 8.0, mint 6.0 / 8.1, sky 5.6 / 7.9, sand 5.1 / 7.4.
        private enum CategoryTone {
            static let sunTint = SwiftUI.Color(light: 0xF6E2A6, dark: 0x4A3A12)
            static let sunGlyph = SwiftUI.Color(light: 0x6B4A00, dark: 0xF6D77A)
            static let asphaltTint = SwiftUI.Color(light: 0xE8DDCB, dark: 0x3A3328)
            static let asphaltGlyph = SwiftUI.Color(light: 0x5A4A35, dark: 0xE6D5B8)
            static let lilacTint = SwiftUI.Color(light: 0xE2DAF4, dark: 0x342C4D)
            static let lilacGlyph = SwiftUI.Color(light: 0x4F3A8C, dark: 0xD2C4F5)
            static let mintTint = SwiftUI.Color(light: 0xCDE8D6, dark: 0x1F3A2C)
            static let mintGlyph = SwiftUI.Color(light: 0x245C3A, dark: 0xA9DDBA)
            static let skyTint = SwiftUI.Color(light: 0xD3E5F4, dark: 0x1D3550)
            static let skyGlyph = SwiftUI.Color(light: 0x1F5A8A, dark: 0xA9D2F5)
            static let sandTint = SwiftUI.Color(light: 0xECE6DA, dark: 0x2E3640)
            static let sandGlyph = SwiftUI.Color(light: 0x5B5F73, dark: 0xD0C8B6)
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
        static let s: CGFloat = 12
        /// Cards, tiles.
        static let m: CGFloat = 16
        /// Buttons inside a card or bar with `Space.xs`…`Space.s` inset: concentric with `m`.
        static let button: CGFloat = 14
        /// Sheets and hero cards.
        static let l: CGFloat = 22
    }

    /// Border widths: hairline at rest, emphasis for focus, selection and errors.
    enum Border {
        static let hairline: CGFloat = 1
        static let emphasis: CGFloat = 2
    }

    /// Dynamic-Type text styles. Titles use the rounded design (the icon's sticker shapes); text stays SF Pro.
    enum Font {
        static let largeTitle = SwiftUI.Font.system(.largeTitle, design: .rounded, weight: .bold)
        static let title = SwiftUI.Font.system(.title2, design: .rounded, weight: .semibold)
        static let title3 = SwiftUI.Font.system(.title3, design: .rounded, weight: .semibold)
        static let headline = SwiftUI.Font.system(.headline, design: .rounded, weight: .semibold)
        static let subheadline = SwiftUI.Font.system(.subheadline, weight: .semibold)
        /// Section headers: one style on every screen.
        static let section = SwiftUI.Font.system(.footnote, weight: .semibold)
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

// MARK: - Display preferences in the environment

extension EnvironmentValues {
    /// Small taps on presses and confirmations; off when the user turns Vibration off in Settings.
    /// Components pass it as `condition:` to `.sensoryFeedback`.
    @Entry var fxHaptics: Bool = true
    /// The iPhone's Reduce Motion OR the in-app toggle (set at the root). Springs become short fades.
    @Entry var fxReduceMotion: Bool = false
}

// MARK: - Pressed state

/// Shared pressed state: a quick opacity dip. `scales` adds a 0.97 squeeze (tiles, primary buttons),
/// dropped under Reduce Motion so nothing moves.
struct FxPressStyle: ButtonStyle {
    var scales: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        FxPressBody(label: configuration.label, isPressed: configuration.isPressed, scales: scales)
    }
}

private struct FxPressBody<Label: View>: View {
    let label: Label
    let isPressed: Bool
    let scales: Bool
    @Environment(\.fxReduceMotion) private var reduceMotion

    var body: some View {
        label
            .opacity(isPressed ? 0.65 : 1)
            .scaleEffect(isPressed && scales && !reduceMotion ? 0.97 : 1)
            .animation(Fx.Motion.press, value: isPressed)
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
