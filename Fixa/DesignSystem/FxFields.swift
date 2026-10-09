import SwiftUI

/// Single-line labelled input with an inline issue message.
struct FxTextField: View {
    enum Kind: Sendable {
        case plain, email, phone
    }

    let title: String
    @Binding var text: String
    var prompt: String = ""
    var kind: Kind = .plain
    var issue: String? = nil

    @FocusState private var focused: Bool

    init(title: String, text: Binding<String>, prompt: String = "", kind: Kind = .plain, issue: String? = nil) {
        self.title = title
        self._text = text
        self.prompt = prompt
        self.kind = kind
        self.issue = issue
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Fx.Space.xs) {
            Text(title)
                .font(Fx.Font.footnote.weight(.semibold))
                .foregroundStyle(Fx.Color.inkSoft)
                .accessibilityHidden(true)
            TextField(text: $text, prompt: Text(prompt).foregroundStyle(Fx.Color.inkSoft.opacity(0.7))) {
                Text(title)
            }
            .font(Fx.Font.body)
            .foregroundStyle(Fx.Color.ink)
            .keyboardType(keyboard)
            .textContentType(contentType)
            .textInputAutocapitalization(kind == .plain ? .sentences : .never)
            .autocorrectionDisabled(kind != .plain)
            .focused($focused)
            .padding(.horizontal, Fx.Space.m)
            .frame(minHeight: Fx.minTarget + 4)
            .background(Fx.Color.card, in: .rect(cornerRadius: Fx.Radius.s, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Fx.Radius.s, style: .continuous)
                    .strokeBorder(borderColor, lineWidth: issue != nil || focused ? 1.5 : 1)
            }
            .accessibilityLabel(Text(title))
            .accessibilityHint(issue.map { Text($0) } ?? Text(""))
            FxIssueText(issue: issue)
        }
    }

    private var borderColor: Color {
        if issue != nil { return Fx.Color.accent }
        return focused ? Fx.Color.sea : Fx.Color.line
    }

    private var keyboard: UIKeyboardType {
        switch kind {
        case .plain: .default
        case .email: .emailAddress
        case .phone: .phonePad
        }
    }

    private var contentType: UITextContentType? {
        switch kind {
        case .plain: nil
        case .email: .emailAddress
        case .phone: .telephoneNumber
        }
    }
}

/// Multi-line labelled input with placeholder and inline issue message.
/// `showsTitle: false` hides the caption when an `FxSectionHeader` above already names the field;
/// `title` still labels the editor for VoiceOver.
struct FxTextEditor: View {
    let title: String
    @Binding var text: String
    var prompt: String = ""
    var issue: String? = nil
    var minHeight: CGFloat = 140
    var showsTitle: Bool = true

    @FocusState private var focused: Bool

    init(
        title: String,
        text: Binding<String>,
        prompt: String = "",
        issue: String? = nil,
        minHeight: CGFloat = 140,
        showsTitle: Bool = true
    ) {
        self.title = title
        self._text = text
        self.prompt = prompt
        self.issue = issue
        self.minHeight = minHeight
        self.showsTitle = showsTitle
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Fx.Space.xs) {
            if showsTitle {
                Text(title)
                    .font(Fx.Font.footnote.weight(.semibold))
                    .foregroundStyle(Fx.Color.inkSoft)
                    .accessibilityHidden(true)
            }
            TextEditor(text: $text)
                .font(Fx.Font.body)
                .foregroundStyle(Fx.Color.ink)
                .scrollContentBackground(.hidden)
                .focused($focused)
                .padding(.horizontal, Fx.Space.s)
                .padding(.vertical, Fx.Space.xs)
                .frame(minHeight: minHeight)
                .overlay(alignment: .topLeading) {
                    if text.isEmpty {
                        Text(prompt)
                            .font(Fx.Font.body)
                            .foregroundStyle(Fx.Color.inkSoft.opacity(0.7))
                            .padding(.horizontal, Fx.Space.m)
                            .padding(.vertical, Fx.Space.m)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
                }
                .background(Fx.Color.card, in: .rect(cornerRadius: Fx.Radius.s, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: Fx.Radius.s, style: .continuous)
                        .strokeBorder(borderColor, lineWidth: issue != nil || focused ? 1.5 : 1)
                }
                .accessibilityLabel(Text(title))
                .accessibilityHint(issue.map { Text($0) } ?? Text(prompt))
            FxIssueText(issue: issue)
        }
    }

    private var borderColor: Color {
        if issue != nil { return Fx.Color.accent }
        return focused ? Fx.Color.sea : Fx.Color.line
    }
}

/// Inline validation message under a field.
private struct FxIssueText: View {
    let issue: String?

    var body: some View {
        if let issue {
            Label {
                Text(issue)
            } icon: {
                Image(systemName: "exclamationmark.circle.fill")
            }
            .font(Fx.Font.footnote)
            .foregroundStyle(Fx.Color.accent)
            .fixedSize(horizontal: false, vertical: true)
            .transition(.opacity)
        }
    }
}

/// Equal square slot for a horizontal photo row: a picked photo with a remove control,
/// an "add" tile (use as the label of a Button or PhotosPicker), or a loading placeholder
/// that reserves the photo's space. Side scales with Dynamic Type.
struct FxPhotoSlot: View {
    private enum Kind {
        case photo(UIImage, label: String, removeLabel: String, onRemove: () -> Void)
        case add(title: String, systemImage: String)
        case loading
    }

    private let kind: Kind
    @ScaledMetric(relativeTo: .footnote) private var side: CGFloat = 80

    /// A picked photo; the corner control removes it.
    init(image: UIImage, label: String, removeLabel: String, onRemove: @escaping () -> Void) {
        kind = .photo(image, label: label, removeLabel: removeLabel, onRemove: onRemove)
    }

    /// Quiet dashed tile with a glyph and a short label. Passive: wrap it in a Button or PhotosPicker.
    init(addTitle: String, systemImage: String) {
        kind = .add(title: addTitle, systemImage: systemImage)
    }

    /// Placeholder with a spinner while a photo loads.
    static var loading: FxPhotoSlot { FxPhotoSlot(kind: .loading) }

    private init(kind: Kind) {
        self.kind = kind
    }

    var body: some View {
        switch kind {
        case let .photo(image, label, removeLabel, onRemove):
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: side, height: side)
                .clipShape(shape)
                .overlay { shape.strokeBorder(Fx.Color.line, lineWidth: 1) }
                .accessibilityLabel(Text(label))
                .overlay(alignment: .topTrailing) {
                    Button(action: onRemove) {
                        Image(systemName: "xmark.circle.fill")
                            .font(Fx.Font.headline)
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, .black.opacity(0.55))
                            .padding(Fx.Space.xs)
                            .frame(width: Fx.minTarget, height: Fx.minTarget, alignment: .topTrailing)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(FxPressStyle())
                    .accessibilityLabel(Text(removeLabel))
                }
                .accessibilityElement(children: .contain)
        case let .add(title, systemImage):
            VStack(spacing: Fx.Space.xs) {
                Image(systemName: systemImage)
                    .font(Fx.Font.headline)
                    .foregroundStyle(Fx.Color.sea)
                    .accessibilityHidden(true)
                Text(title)
                    .font(Fx.Font.footnote)
                    .foregroundStyle(Fx.Color.ink)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
            }
            .padding(Fx.Space.xs)
            .frame(width: side, height: side)
            .background(Fx.Color.card, in: shape)
            .overlay {
                shape.strokeBorder(Fx.Color.inkSoft.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            }
            .contentShape(shape)
        case .loading:
            ProgressView()
                .frame(width: side, height: side)
                .background(Fx.Color.card, in: shape)
                .overlay { shape.strokeBorder(Fx.Color.line, lineWidth: 1) }
        }
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Fx.Radius.s, style: .continuous)
    }
}
