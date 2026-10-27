import SwiftUI

/// Bar pinned to the bottom edge, in the thumb zone: paper background, 1 pt hairline on top.
/// Holds the screen's primary action. Use through `.fxBottomBar { … }`.
struct FxBottomBar<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(spacing: Fx.Space.s) {
            content
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, Fx.Space.l)
        .padding(.top, Fx.Space.m)
        .padding(.bottom, Fx.Space.s)
        .background {
            Fx.Color.paper.ignoresSafeArea(edges: .bottom)
        }
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Fx.Color.line)
                .frame(height: Fx.Border.hairline)
                .accessibilityHidden(true)
        }
    }
}

extension View {
    /// Pins `content` in an `FxBottomBar` below the view; scroll content insets above it.
    func fxBottomBar<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        let bar = FxBottomBar(content: content)
        return safeAreaInset(edge: .bottom, spacing: 0) {
            bar
        }
    }
}
