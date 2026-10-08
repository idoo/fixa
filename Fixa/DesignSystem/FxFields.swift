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
struct FxTextEditor: View {
    let title: String
    @Binding var text: String
    var prompt: String = ""
    var issue: String? = nil
    var minHeight: CGFloat = 140

    @FocusState private var focused: Bool

    init(title: String, text: Binding<String>, prompt: String = "", issue: String? = nil, minHeight: CGFloat = 140) {
        self.title = title
        self._text = text
        self.prompt = prompt
        self.issue = issue
        self.minHeight = minHeight
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Fx.Space.xs) {
            Text(title)
                .font(Fx.Font.footnote.weight(.semibold))
                .foregroundStyle(Fx.Color.inkSoft)
                .accessibilityHidden(true)
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
