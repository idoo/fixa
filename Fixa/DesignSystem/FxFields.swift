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
                .font(Fx.Font.subheadline)
                .foregroundStyle(Fx.Color.ink)
                .accessibilityHidden(true)
            TextField(text: $text, prompt: Text(prompt).foregroundStyle(Fx.Color.ink2)) {
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
            .fxOutline(RoundedRectangle(cornerRadius: Fx.Radius.s, style: .continuous), outline: borderColor, width: borderWidth)
            .accessibilityLabel(Text(title))
            .accessibilityHint(issue.map { Text($0) } ?? Text(""))
            FxIssueText(issue: issue)
        }
    }

    private var borderColor: Color {
        if issue != nil { return Fx.Color.error }
        return focused ? Fx.Color.sea : Fx.Color.line
    }

    private var borderWidth: CGFloat {
        issue != nil || focused ? Fx.Border.emphasis : Fx.Border.hairline
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
                    .font(Fx.Font.subheadline)
                    .foregroundStyle(Fx.Color.ink)
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
                            .foregroundStyle(Fx.Color.ink2)
                            .padding(.horizontal, Fx.Space.m)
                            .padding(.vertical, Fx.Space.m)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
                }
                .fxOutline(RoundedRectangle(cornerRadius: Fx.Radius.s, style: .continuous), outline: borderColor, width: borderWidth)
                .accessibilityLabel(Text(title))
                .accessibilityHint(issue.map { Text($0) } ?? Text(prompt))
            FxIssueText(issue: issue)
        }
    }

    private var borderColor: Color {
        if issue != nil { return Fx.Color.error }
        return focused ? Fx.Color.sea : Fx.Color.line
    }

    private var borderWidth: CGFloat {
        issue != nil || focused ? Fx.Border.emphasis : Fx.Border.hairline
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
            .font(Fx.Font.footnote.weight(.semibold))
            .foregroundStyle(Fx.Color.error)
            .fixedSize(horizontal: false, vertical: true)
            .transition(.opacity)
        }
    }
}

/// Equal square slot for a horizontal photo row: a picked photo with a remove control,
/// an "add" slot (label of a Button or PhotosPicker with `FxPressStyle`), or a loading placeholder
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

    /// Bordered card slot with a sea glyph and a short label. Passive: wrap it in a Button or PhotosPicker.
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
                .overlay { shape.strokeBorder(Fx.Color.line, lineWidth: Fx.Border.hairline) }
                .accessibilityLabel(Text(label))
                .overlay(alignment: .topTrailing) {
                    Button(action: onRemove) {
                        Image(systemName: "xmark")
                            .font(Fx.Font.footnote.weight(.bold))
                            .foregroundStyle(Fx.Color.ink)
                            .frame(width: 26, height: 26)
                            .fxOutline(Circle())
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
                    .font(Fx.Font.footnote.weight(.semibold))
                    .foregroundStyle(Fx.Color.ink)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
            }
            .padding(Fx.Space.xs)
            .frame(width: side, height: side)
            .fxOutline(shape)
            .contentShape(shape)
        case .loading:
            ProgressView()
                .frame(width: side, height: side)
                .fxOutline(shape)
        }
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Fx.Radius.s, style: .continuous)
    }
}
