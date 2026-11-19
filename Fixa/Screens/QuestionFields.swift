import FixaKit
import SwiftUI

/// One adapter question in the app's own controls, bound to `model.draft.answers[question.id]`.
/// Answers are stored as the form wants them: typed text, the option's Swedish `value`, every
/// ticked value, or an ISO 8601 date-time with offset.
struct QuestionField: View {
    let question: AdapterSpec.Question
    let spec: AdapterSpec
    /// VoiceOver focus of the Report screen's first issue (question id).
    var a11yFocus: AccessibilityFocusState<String?>.Binding
    /// Keyboard focus of the Report screen's first issue (question id), for text kinds.
    var keyboardFocus: FocusState<String?>.Binding

    @Environment(AppModel.self) private var model
    @Environment(\.fxHaptics) private var haptics
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// Bumped by every choose, tick and suggestion: drives the selection haptic.
    @State private var taps = 0

    /// Scroll target of a question on the Report screen.
    static func scrollID(_ questionID: String) -> String { "report.question.\(questionID)" }

    private var title: String { question.title.resolve(L10n.locale) }
    private var issue: String? { model.issue(forQuestion: question.id)?.message(in: spec) }
    private var values: [String] { model.draft.answers[question.id] ?? [] }

    var body: some View {
        VStack(alignment: .leading, spacing: Fx.Space.s) {
            FxSectionHeader(
                title,
                subtitle: question.required ? nil : String(localized: "Optional", bundle: L10n.bundle, locale: L10n.locale)
            )
            .accessibilityValue(issue.map { Text($0) } ?? Text(""))
            .accessibilityFocused(a11yFocus, equals: question.id)
            if let hint = question.hint?.resolve(L10n.locale) {
                Text(hint)
                    .font(Fx.Font.footnote)
                    .foregroundStyle(Fx.Color.ink2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            control
            if let issue, question.kind != .text, question.kind != .longText {
                QuestionIssueText(message: issue)
            }
        }
        .sensoryFeedback(.selection, trigger: taps) { _, _ in haptics }
        // `.contain` first: an identifier on a plain container overrides every child's own
        // (`.option.<i>`, `.suggestion.<i>`, `.field`, `.menu`), so UI tests couldn't find them.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(Self.scrollID(question.id))
    }

    @ViewBuilder
    private var control: some View {
        switch question.kind {
        case .text: textControl
        case .longText: longTextControl
        case .choice:
            if (question.options ?? []).count > Self.listLimit {
                choiceMenu
            } else {
                optionRows(multiple: false)
            }
        case .multiChoice: optionRows(multiple: true)
        case .dateTime: dateTimeControl
        }
    }

    /// More options than this go behind a menu (a list of 23 stations would bury the rest of the form).
    private static let listLimit = 7

    // MARK: Text

    private var textBinding: Binding<String> {
        Binding(
            get: { values.first ?? "" },
            set: { model.draft.answers[question.id] = $0.isEmpty ? nil : [$0] }
        )
    }

    private var isCode: Bool { question.id == "registration" }

    private var textControl: some View {
        let suggestions = question.suggestions ?? []
        return VStack(alignment: .leading, spacing: Fx.Space.s) {
            FxTextField(
                title: title,
                text: textBinding,
                kind: isCode ? .code : .plain,
                issue: issue,
                showsTitle: false
            )
            .focused(keyboardFocus, equals: question.id)
            .accessibilityIdentifier("report.question.\(question.id).field")
            if !suggestions.isEmpty {
                FlowLayout(spacing: Fx.Space.s) {
                    ForEach(Array(suggestions.enumerated()), id: \.offset) { index, suggestion in
                        suggestionChip(suggestion, index: index)
                    }
                }
            }
        }
    }

    /// Reads in the app's language, fills in the Swedish value: the kommun reads Swedish.
    private func suggestionChip(_ suggestion: AdapterSpec.QuestionOption, index: Int) -> some View {
        let current = (values.first ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let chosen = current.caseInsensitiveCompare(suggestion.value) == .orderedSame
        let label = suggestion.title.resolve(L10n.locale)
        return Button {
            taps += 1
            guard !chosen else { return }
            model.draft.answers[question.id] = [suggestion.value]
        } label: {
            HStack(spacing: Fx.Space.xs) {
                Image(systemName: chosen ? "checkmark" : "plus")
                    .font(Fx.Font.footnote.weight(.bold))
                    .accessibilityHidden(true)
                Text(label)
                    .font(Fx.Font.callout)
                    .multilineTextAlignment(.leading)
            }
            .foregroundStyle(chosen ? Fx.Color.sea : Fx.Color.ink)
            .padding(.horizontal, Fx.Space.m)
            .frame(minHeight: Fx.minTarget)
            .background(Fx.Color.card, in: Capsule())
            .overlay {
                Capsule().strokeBorder(chosen ? Fx.Color.sea : Fx.Color.fieldBorder, lineWidth: chosen ? Fx.Border.emphasis : Fx.Border.hairline)
            }
            .contentShape(Capsule())
        }
        .buttonStyle(FxPressStyle())
        .accessibilityLabel(Text(label))
        .accessibilityHint(chosen ? Text("") : Text("Fills in the answer in Swedish"))
        .accessibilityAddTraits(chosen ? .isSelected : [])
        .accessibilityIdentifier("report.question.\(question.id).suggestion.\(index)")
    }

    private var longTextControl: some View {
        FxTextEditor(
            title: title,
            text: textBinding,
            prompt: question.hint?.resolve(L10n.locale) ?? "",
            issue: issue,
            minHeight: 100,
            showsTitle: false
        )
        .focused(keyboardFocus, equals: question.id)
        .accessibilityIdentifier("report.question.\(question.id).field")
    }

    // MARK: Choices

    /// Ticks `value` (several) or chooses it (one). Ticked values keep the options' order.
    private func pick(_ value: String, multiple: Bool) {
        taps += 1
        guard multiple else {
            model.draft.answers[question.id] = [value]
            return
        }
        var ticked = Set(values)
        if ticked.contains(value) { ticked.remove(value) } else { ticked.insert(value) }
        let ordered = (question.options ?? []).map(\.value).filter(ticked.contains)
        model.draft.answers[question.id] = ordered.isEmpty ? nil : ordered
    }

    private func optionRows(multiple: Bool) -> some View {
        let options = question.options ?? []
        return FxCard {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(options.enumerated()), id: \.offset) { index, option in
                    if index > 0 { FxDivider() }
                    optionRow(option, index: index, multiple: multiple)
                }
            }
        }
    }

    private func optionRow(_ option: AdapterSpec.QuestionOption, index: Int, multiple: Bool) -> some View {
        let selected = values.contains(option.value)
        let label = option.title.resolve(L10n.locale)
        let symbol = multiple
            ? (selected ? "checkmark.square.fill" : "square")
            : (selected ? "checkmark.circle.fill" : "circle")
        return Button {
            pick(option.value, multiple: multiple)
        } label: {
            HStack(spacing: Fx.Space.m) {
                Image(systemName: symbol)
                    .font(Fx.Font.headline)
                    .foregroundStyle(selected ? Fx.Color.sea : Fx.Color.ink2)
                    .accessibilityHidden(true)
                Text(label)
                    .font(Fx.Font.body)
                    .foregroundStyle(Fx.Color.ink)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, minHeight: Fx.minTarget, alignment: .leading)
            .contentShape(.rect)
        }
        .buttonStyle(FxPressStyle())
        .accessibilityLabel(Text(label))
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("report.question.\(question.id).option.\(index)")
    }

    /// A long single-choice list as a menu card: the chosen option, or "Choose", and "Change".
    private var choiceMenu: some View {
        let options = question.options ?? []
        let chosen = options.first { values.contains($0.value) }?.title.resolve(L10n.locale)
        let rowLayout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Fx.Space.xs))
            : AnyLayout(HStackLayout(spacing: Fx.Space.m))
        return Menu {
            ForEach(Array(options.enumerated()), id: \.offset) { index, option in
                Button {
                    pick(option.value, multiple: false)
                } label: {
                    if values.contains(option.value) {
                        Label(option.title.resolve(L10n.locale), systemImage: "checkmark")
                    } else {
                        Text(option.title.resolve(L10n.locale))
                    }
                }
                .accessibilityIdentifier("report.question.\(question.id).option.\(index)")
            }
        } label: {
            FxCard {
                rowLayout {
                    Text(chosen ?? String(localized: "Choose", bundle: L10n.bundle, locale: L10n.locale))
                        .font(Fx.Font.headline)
                        .foregroundStyle(chosen == nil ? Fx.Color.ink2 : Fx.Color.ink)
                        .multilineTextAlignment(.leading)
                    if !dynamicTypeSize.isAccessibilitySize {
                        Spacer(minLength: Fx.Space.s)
                    }
                    Text(chosen == nil ? String(localized: "Choose", bundle: L10n.bundle, locale: L10n.locale) : String(localized: "Change", bundle: L10n.bundle, locale: L10n.locale))
                        .font(Fx.Font.callout)
                        .foregroundStyle(Fx.Color.sea)
                        .accessibilityHidden(chosen == nil)
                }
                .frame(maxWidth: .infinity, minHeight: Fx.minTarget, alignment: .leading)
            }
        }
        .buttonStyle(FxPressStyle())
        .accessibilityLabel(Text(verbatim: "\(title): \(chosen ?? String(localized: "Choose", bundle: L10n.bundle, locale: L10n.locale))"))
        .accessibilityValue(issue.map { Text($0) } ?? Text(""))
        .accessibilityInputLabels([Text(verbatim: title), Text("Change")])
        .accessibilityIdentifier("report.question.\(question.id).menu")
    }

    // MARK: Date and time

    /// ISO 8601 with the phone's offset, e.g. `2026-11-19T10:00:00+01:00`.
    private static func isoString(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = .current
        return formatter.string(from: date)
    }

    private var dateBinding: Binding<Date> {
        Binding(
            get: { values.first.flatMap { ISO8601DateFormatter().date(from: $0) } ?? .now },
            set: { model.draft.answers[question.id] = [Self.isoString(min($0, .now))] }
        )
    }

    /// A system picker plays its own haptics; the wrapper adds none.
    private var dateTimeControl: some View {
        DatePicker(
            selection: dateBinding,
            in: ...Date.now,
            displayedComponents: [.date, .hourAndMinute]
        ) {
            Text(verbatim: title)
        }
        .labelsHidden()
        .environment(\.locale, L10n.locale)
        .frame(maxWidth: .infinity, minHeight: Fx.minTarget, alignment: .leading)
        .accessibilityLabel(Text(verbatim: title))
        .accessibilityValue(issue.map { Text($0) } ?? Text(""))
        .accessibilityIdentifier("report.question.\(question.id).date")
        .onAppear {
            // Defaults to now, written so the answer is there even if the picker is never touched.
            if values.isEmpty {
                model.draft.answers[question.id] = [Self.isoString(.now)]
            }
        }
    }
}

/// An answer formatted for reading: option titles, a suggestion's title, or the date-time in the
/// app's language. Review shows it; the kommun gets `ReportComposer.formValues`.
enum QuestionAnswerText {
    static func text(_ question: AdapterSpec.Question, values: [String]) -> String {
        switch question.kind {
        case .choice, .multiChoice:
            let options = question.options ?? []
            return values.map { value in
                options.first { $0.value == value }?.title.resolve(L10n.locale) ?? value
            }
            .joined(separator: ", ")
        case .text, .longText:
            let suggestions = question.suggestions ?? []
            return values.map { value in
                suggestions.first { $0.value.caseInsensitiveCompare(value) == .orderedSame }?.title.resolve(L10n.locale) ?? value
            }
            .joined(separator: ", ")
        case .dateTime:
            let parser = ISO8601DateFormatter()
            return values.map { value in
                parser.date(from: value)?.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).locale(L10n.locale)) ?? value
            }
            .joined(separator: ", ")
        }
    }
}

/// Inline issue under a choice or date question; the control's value already reads it to VoiceOver.
private struct QuestionIssueText: View {
    let message: String

    var body: some View {
        Label(message, systemImage: "exclamationmark.circle")
            .font(Fx.Font.footnote)
            .foregroundStyle(Fx.Color.error)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityHidden(true)
    }
}
