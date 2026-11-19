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
    /// Where a picked photo was taken: the first reference for options with a place.
    var photoPlace: Coordinate? = nil

    @Environment(AppModel.self) private var model
    @Environment(\.fxHaptics) private var haptics
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.fxReduceMotion) private var reduceMotion
    /// Bumped by every choose, tick and suggestion: drives the selection haptic.
    @State private var taps = 0
    /// Current position read without asking (precise location already allowed) or by "Find the nearest".
    @State private var deviceFix: Coordinate?
    /// True once "Find the nearest" found the position: it then wins over the photo's place.
    @State private var deviceFixIsExplicit = false
    /// The option Fixa chose as the nearest; a manual pick clears it.
    @State private var nearestPick: String?
    @State private var isFindingNearest = false
    @State private var nearestFailure: String?
    /// Bumped by "Find the nearest": drives the selection haptic.
    @State private var nearestTaps = 0
    /// Bumped when "Find the nearest" picks a station: drives the success haptic.
    @State private var nearestFound = 0
    /// Bumped when "Find the nearest" fails: drives the error haptic.
    @State private var nearestFailed = 0

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
            if hasLocatedOptions {
                nearestButton
                nearestStatus
            }
            if let issue, question.kind != .text, question.kind != .longText {
                QuestionIssueText(message: issue)
            }
        }
        .sensoryFeedback(.selection, trigger: taps) { _, _ in haptics }
        .sensoryFeedback(.selection, trigger: nearestTaps) { _, _ in haptics }
        .sensoryFeedback(.success, trigger: nearestFound) { _, _ in haptics }
        .sensoryFeedback(.error, trigger: nearestFailed) { _, _ in haptics }
        .task(id: hasLocatedOptions) {
            guard hasLocatedOptions else { return }
            await readQuietFix()
            autoFillNearest()
        }
        .onChange(of: photoPlace) { _, _ in autoFillNearest() }
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

    /// Shows a suggestion's answer by its title in the app's language; stores the Swedish `value`.
    /// Typed text equal to a suggestion's title stores that suggestion's value; other text as typed.
    private var textBinding: Binding<String> {
        let suggestions = question.suggestions ?? []
        return Binding(
            get: {
                let value = values.first ?? ""
                return suggestions.first { $0.value.caseInsensitiveCompare(value) == .orderedSame }?
                    .title.resolve(L10n.locale) ?? value
            },
            set: { text in
                guard !text.isEmpty else {
                    model.draft.answers[question.id] = nil
                    return
                }
                let match = suggestions.first {
                    $0.title.resolve(L10n.locale).compare(text, options: [.caseInsensitive, .diacriticInsensitive], locale: L10n.locale) == .orderedSame
                }
                model.draft.answers[question.id] = [match?.value ?? text]
            }
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
        withAnimation(reduceMotion ? nil : Fx.Motion.select) {
            nearestPick = nil
            nearestFailure = nil
        }
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
        // A checkbox reads its state ticked or not; a single choice reads "Selected" on the chosen one.
        .accessibilityValue(multiple ? (selected ? Text("Ticked") : Text("Not ticked")) : Text(""))
        .accessibilityAddTraits(!multiple && selected ? .isSelected : [])
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
            ForEach(Array(menuOptions.enumerated()), id: \.offset) { index, entry in
                let option = entry.option
                Button {
                    pick(option.value, multiple: false)
                } label: {
                    // Menu rows read Text, Text, Image as title, subtitle and icon; a Label drops the subtitle.
                    Text(option.title.resolve(L10n.locale))
                    if let meters = entry.meters { Text(Self.distanceText(meters)) }
                    if values.contains(option.value) { Image(systemName: "checkmark") }
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

    // MARK: Nearest place

    /// An automatic pick farther than this is likely wrong, so the field stays empty instead.
    private static let autoFillMeters: Double = 500

    private var hasLocatedOptions: Bool {
        question.kind == .choice && (question.options ?? []).contains { $0.location != nil }
    }

    /// Where "nearest" is measured from. It stays on the phone and in this view only.
    private var reference: (point: Coordinate, fromPhoto: Bool)? {
        if deviceFixIsExplicit, let deviceFix { return (deviceFix, false) }
        if let photoPlace { return (photoPlace, true) }
        return deviceFix.map { ($0, false) }
    }

    /// Options as the menu shows them: with a reference, located ones nearest first, then the rest
    /// in adapter order.
    private var menuOptions: [(option: AdapterSpec.QuestionOption, meters: Double?)] {
        let options = question.options ?? []
        guard let reference else { return options.map { (option: $0, meters: nil) } }
        let located: [(option: AdapterSpec.QuestionOption, meters: Double?)] = question
            .locatedOptions(nearestTo: reference.point)
            .map { (option: $0.option, meters: $0.meters) }
        return located + options.filter { $0.location == nil }.map { (option: $0, meters: nil) }
    }

    static func distanceText(_ meters: Double) -> String {
        Measurement(value: meters, unit: UnitLength.meters)
            .formatted(.measurement(width: .abbreviated, usage: .road).locale(L10n.locale))
    }

    /// "Nearest to you · 350 m" for the option Fixa chose, while it is still the answer.
    private var nearestNote: String? {
        guard let nearestPick, values == [nearestPick], let reference,
              let place = question.options?.first(where: { $0.value == nearestPick })?.location else { return nil }
        return Self.nearestNote(meters: reference.point.distance(to: place), fromPhoto: reference.fromPhoto)
    }

    private static func nearestNote(meters: Double, fromPhoto: Bool) -> String {
        let distance = distanceText(meters)
        return fromPhoto
            ? String(localized: "Nearest to where the photo was taken · \(distance)", bundle: L10n.bundle, locale: L10n.locale)
            : String(localized: "Nearest to you · \(distance)", bundle: L10n.bundle, locale: L10n.locale)
    }

    /// The nearest note or the failure, in a line that is always reserved for the longest of them:
    /// a result landing seconds later fades in place instead of pushing the form down.
    private var nearestStatus: some View {
        ZStack(alignment: .topLeading) {
            ForEach([
                Self.nearestNote(meters: 10_000, fromPhoto: true),
                Self.message(for: .denied),
                Self.message(for: .servicesOff),
                Self.message(for: .unavailable),
            ], id: \.self) { longest in
                Text(longest)
                    .hidden()
                    .accessibilityHidden(true)
            }
            if let nearestFailure {
                Text(nearestFailure)
                    .transition(.opacity)
            } else if let nearestNote {
                Text(nearestNote)
                    .transition(.opacity)
                    .accessibilityIdentifier("report.question.\(question.id).nearestNote")
            }
        }
        .font(Fx.Font.footnote)
        .foregroundStyle(Fx.Color.ink2)
        .multilineTextAlignment(.leading)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Explicit: may ask for location permission, then picks the nearest option at any distance.
    private var nearestButton: some View {
        Button(action: findNearest) {
            Label {
                // Both labels lay out so the longer one sets the height: no jump when it switches.
                ZStack(alignment: .topLeading) {
                    Text(String(localized: "Finding where you are…", bundle: L10n.bundle, locale: L10n.locale))
                        .opacity(isFindingNearest ? 1 : 0)
                        .accessibilityHidden(!isFindingNearest)
                    Text(String(localized: "Find the nearest", bundle: L10n.bundle, locale: L10n.locale))
                        .opacity(isFindingNearest ? 0 : 1)
                        .accessibilityHidden(isFindingNearest)
                }
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "location.fill")
                    .accessibilityHidden(true)
            }
            .font(Fx.Font.callout.weight(.semibold))
            .foregroundStyle(Fx.Color.sea)
            .frame(maxWidth: .infinity, minHeight: Fx.minTarget, alignment: .leading)
            .contentShape(.rect)
        }
        .buttonStyle(FxPressStyle())
        .disabled(isFindingNearest)
        .accessibilityIdentifier("report.question.\(question.id).nearest")
    }

    private func findNearest() {
        guard !isFindingNearest else { return }
        nearestTaps += 1
        withAnimation(reduceMotion ? nil : Fx.Motion.select) { nearestFailure = nil }
        isFindingNearest = true
        Task {
            defer { isFindingNearest = false }
            do {
                let fix = try await LocationProvider.currentFix(timeout: .seconds(10), accuracy: 1000)
                deviceFix = fix.coordinate
                deviceFixIsExplicit = true
                guard let nearest = question.locatedOptions(nearestTo: fix.coordinate).first else { return }
                withAnimation(reduceMotion ? nil : Fx.Motion.select) {
                    model.draft.answers[question.id] = [nearest.option.value]
                    nearestPick = nearest.option.value
                }
                nearestFound += 1
                let station = nearest.option.title.resolve(L10n.locale)
                let note = Self.nearestNote(meters: nearest.meters, fromPhoto: false)
                AccessibilityNotification.Announcement("\(station), \(note)").post()
            } catch {
                let failure = (error as? LocationProvider.Failure) ?? .unavailable
                let message = Self.message(for: failure)
                withAnimation(reduceMotion ? nil : Fx.Motion.select) { nearestFailure = message }
                nearestFailed += 1
                AccessibilityNotification.Announcement(message).post()
            }
        }
    }

    /// The map sheet's wording for the same failures.
    private static func message(for failure: LocationProvider.Failure) -> String {
        switch failure {
        case .denied, .restricted: String(localized: "Fixa isn't allowed to use your location", bundle: L10n.bundle, locale: L10n.locale)
        case .servicesOff: String(localized: "Location Services are off on this iPhone", bundle: L10n.bundle, locale: L10n.locale)
        case .unavailable, .timedOut: String(localized: "Couldn't find where you are", bundle: L10n.bundle, locale: L10n.locale)
        }
    }

    /// Reads the position without asking, only when precise location is already allowed (the same
    /// rule as the pin's prefill).
    private func readQuietFix() async {
        guard deviceFix == nil, await LocationProvider.access() == .allowed(precise: true),
              let fix = try? await LocationProvider.currentFix(timeout: .seconds(10), accuracy: 100),
              !fix.isApproximate, deviceFix == nil else { return }
        deviceFix = fix.coordinate
    }

    /// Passive: fills an empty answer with an option within `autoFillMeters`. Never replaces an
    /// answer, chosen or restored from a draft. Silent.
    private func autoFillNearest() {
        guard values.isEmpty, let reference,
              let nearest = question.locatedOptions(nearestTo: reference.point).first,
              nearest.meters <= Self.autoFillMeters else { return }
        withAnimation(reduceMotion ? nil : Fx.Motion.select) {
            model.draft.answers[question.id] = [nearest.option.value]
            nearestPick = nearest.option.value
            nearestFailure = nil
        }
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
