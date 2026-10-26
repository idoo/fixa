import SwiftUI

/// Filled Falu-red call to action. One per screen. Impact haptic on tap.
struct FxPrimaryButton: View {
    let title: String
    var systemImage: String? = nil
    var isLoading: Bool = false
    let action: () -> Void

    @State private var taps = 0

    init(title: String, systemImage: String? = nil, isLoading: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.isLoading = isLoading
        self.action = action
    }

    var body: some View {
        Button {
            guard !isLoading else { return }
            taps += 1
            action()
        } label: {
            HStack(spacing: Fx.Space.s) {
                if isLoading {
                    ProgressView()
                        .tint(Fx.Color.onAccent)
                        .accessibilityHidden(true)
                } else if let systemImage {
                    Image(systemName: systemImage)
                        .imageScale(.medium)
                        .accessibilityHidden(true)
                }
                Text(title)
                    .font(Fx.Font.headline)
                    .multilineTextAlignment(.center)
            }
            .foregroundStyle(Fx.Color.onAccent)
            .frame(maxWidth: .infinity, minHeight: 52)
            .padding(.horizontal, Fx.Space.l)
            .padding(.vertical, Fx.Space.xs)
            .background(Fx.Color.accent, in: .rect(cornerRadius: Fx.Radius.m, style: .continuous))
            .contentShape(.rect(cornerRadius: Fx.Radius.m, style: .continuous))
        }
        .buttonStyle(FxPressStyle())
        .disabled(isLoading)
        .sensoryFeedback(.impact(weight: .medium), trigger: taps)
        .accessibilityLabel(Text(title))
        .accessibilityValue(isLoading ? Text(String(localized: "Loading…", comment: "Accessibility value on a busy button")) : Text(""))
    }
}

/// Outlined, quiet companion button.
struct FxSecondaryButton: View {
    let title: String
    var systemImage: String? = nil
    let action: () -> Void

    @State private var taps = 0

    init(title: String, systemImage: String? = nil, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.action = action
    }

    var body: some View {
        Button {
            taps += 1
            action()
        } label: {
            FxSecondaryLabel(title: title, systemImage: systemImage)
        }
        .buttonStyle(FxPressStyle())
        .sensoryFeedback(.impact(weight: .light), trigger: taps)
        .accessibilityLabel(Text(title))
    }
}

/// The look of `FxSecondaryButton`, for controls that bring their own action (e.g. `PhotosPicker`).
/// Pair with `.buttonStyle(FxPressStyle())`.
struct FxSecondaryLabel: View {
    let title: String
    var systemImage: String? = nil

    var body: some View {
        HStack(spacing: Fx.Space.s) {
            if let systemImage {
                Image(systemName: systemImage)
                    .imageScale(.medium)
                    .accessibilityHidden(true)
            }
            Text(title)
                .font(Fx.Font.headline)
                .multilineTextAlignment(.center)
        }
        .foregroundStyle(Fx.Color.ink)
        .frame(maxWidth: .infinity, minHeight: 48)
        .padding(.horizontal, Fx.Space.l)
        .padding(.vertical, Fx.Space.xs)
        .background(Fx.Color.card, in: .rect(cornerRadius: Fx.Radius.m, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Fx.Radius.m, style: .continuous)
                .strokeBorder(Fx.Color.line, lineWidth: 1)
        }
        .contentShape(.rect(cornerRadius: Fx.Radius.m, style: .continuous))
    }
}

/// Round icon-only control, e.g. floating over a map. `label` is read by VoiceOver.
struct FxIconButton: View {
    let systemImage: String
    let label: String
    var isLoading: Bool = false
    let action: () -> Void

    @State private var taps = 0

    init(systemImage: String, label: String, isLoading: Bool = false, action: @escaping () -> Void) {
        self.systemImage = systemImage
        self.label = label
        self.isLoading = isLoading
        self.action = action
    }

    var body: some View {
        Button {
            guard !isLoading else { return }
            taps += 1
            action()
        } label: {
            ZStack {
                if isLoading {
                    ProgressView()
                        .tint(Fx.Color.ink)
                } else {
                    Image(systemName: systemImage)
                        .font(Fx.Font.headline)
                        .foregroundStyle(Fx.Color.ink)
                }
            }
            .frame(width: 48, height: 48)
            .background(Fx.Color.card, in: Circle())
            .overlay(Circle().strokeBorder(Fx.Color.line, lineWidth: 1))
            .contentShape(Circle())
        }
        .buttonStyle(FxPressStyle())
        .sensoryFeedback(.impact(weight: .light), trigger: taps)
        .accessibilityLabel(Text(label))
    }
}

/// Raised surface for grouping content.
struct FxCard<Content: View>: View {
    @ViewBuilder let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Fx.Space.m) {
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Fx.Space.l)
        .background(Fx.Color.card, in: .rect(cornerRadius: Fx.Radius.m, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Fx.Radius.m, style: .continuous)
                .strokeBorder(Fx.Color.line, lineWidth: 1)
        }
    }
}

/// Large square-ish category tile for a 2-column grid. Selection haptic.
struct FxTile: View {
    let title: String
    let systemImage: String
    var isSelected: Bool = false
    let action: () -> Void

    @State private var taps = 0

    init(title: String, systemImage: String, isSelected: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.isSelected = isSelected
        self.action = action
    }

    var body: some View {
        Button {
            taps += 1
            action()
        } label: {
            VStack(alignment: .leading, spacing: Fx.Space.m) {
                Image(systemName: systemImage)
                    .font(.system(.title2, weight: .regular))
                    .foregroundStyle(isSelected ? Fx.Color.onAccent : Fx.Color.accent)
                    .frame(width: 44, height: 44)
                    .background(
                        isSelected ? Fx.Color.accent : Fx.Color.accent.opacity(0.10),
                        in: .circle
                    )
                    .accessibilityHidden(true)
                Spacer(minLength: 0)
                Text(title)
                    .font(Fx.Font.headline)
                    .foregroundStyle(Fx.Color.ink)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(Fx.Space.l)
            .frame(maxWidth: .infinity, minHeight: 128, alignment: .topLeading)
            .background(Fx.Color.card, in: .rect(cornerRadius: Fx.Radius.l, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Fx.Radius.l, style: .continuous)
                    .strokeBorder(isSelected ? Fx.Color.accent : Fx.Color.line, lineWidth: isSelected ? 2 : 1)
            }
            .contentShape(.rect(cornerRadius: Fx.Radius.l, style: .continuous))
            .animation(Fx.Motion.select, value: isSelected)
        }
        .buttonStyle(FxPressStyle())
        .sensoryFeedback(.selection, trigger: taps)
        .accessibilityLabel(Text(title))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
