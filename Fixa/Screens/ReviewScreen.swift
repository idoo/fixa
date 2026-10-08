import FixaKit
import MapKit
import SwiftUI
import UIKit

/// Exactly what will be sent, then Send with progress and fallbacks.
struct ReviewScreen: View {
    let spec: AdapterSpec
    @Environment(AppModel.self) private var model
    @State private var isMailPresented = false
    @State private var isSharePresented = false
    @State private var copied = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Fx.Space.xl) {
                FxSectionHeader(
                    String(localized: "Check before sending"),
                    subtitle: String(localized: "This is what \(spec.municipality.name) will receive.")
                )
                summaryCard
                if model.options.dryRun {
                    FxBanner(
                        kind: .info,
                        title: String(localized: "Test mode"),
                        message: String(localized: "Fixa stops before the last step. Nothing is submitted.")
                    )
                }
                FxBanner(kind: .info, title: String(localized: "Good to know"), message: spec.disclaimer.resolve())
                sendSection
            }
            .padding(Fx.Space.l)
        }
        .fxScreenBackground()
        .navigationTitle(Text("Review"))
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(model.submission.isSending)
        .sheet(isPresented: $isMailPresented) {
            MailComposer(
                recipients: [spec.fallbackEmail].compactMap { $0 },
                subject: MailFallback.subject(model.draft, spec: spec),
                body: MailFallback.body(model.draft, spec: spec),
                attachment: model.draft.photoJPEG.map {
                    MailComposer.Attachment(data: $0, mimeType: "image/jpeg", fileName: "fixa.jpg")
                },
                onFinish: { _ in isMailPresented = false }
            )
            .ignoresSafeArea()
        }
        .sheet(isPresented: $isSharePresented) {
            ShareSheet(items: shareItems)
                .presentationDetents([.medium, .large])
        }
    }

    // MARK: Summary

    private var summaryCard: some View {
        FxCard {
            row(String(localized: "Category"), value: spec.category(for: model.draft)?.title.resolve() ?? "–")
            divider
            row(String(localized: "Place"), value: ReportComposer.placeText(for: model.draft))
            if let coordinate = model.draft.coordinate {
                Map(initialPosition: .region(MKCoordinateRegion(
                    center: coordinate.clLocation,
                    latitudinalMeters: 400,
                    longitudinalMeters: 400
                )), interactionModes: []) {
                    Marker(model.draft.locationText, coordinate: coordinate.clLocation)
                        .tint(Fx.Color.accent)
                }
                .frame(height: 120)
                .clipShape(RoundedRectangle(cornerRadius: Fx.Radius.s))
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
            divider
            VStack(alignment: .leading, spacing: Fx.Space.xs) {
                label(String(localized: "Description, as sent"))
                Text(ReportComposer.description(for: model.draft, spec: spec))
                    .font(Fx.Font.body)
                    .foregroundStyle(Fx.Color.ink)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            divider
            VStack(alignment: .leading, spacing: Fx.Space.xs) {
                label(String(localized: "Photo"))
                if let data = model.draft.photoJPEG, let image = UIImage(data: data) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 200)
                        .clipShape(RoundedRectangle(cornerRadius: Fx.Radius.s))
                        .accessibilityLabel(Text("Attached photo"))
                } else {
                    Text("No photo")
                        .font(Fx.Font.body)
                        .foregroundStyle(Fx.Color.inkSoft)
                }
            }
            divider
            row(String(localized: "Reply"), value: replySummary)
        }
    }

    private var replySummary: String {
        guard model.draft.wantsFeedback else { return String(localized: "No reply requested") }
        let c = model.draft.contact
        let name = [c.firstName, c.lastName].filter { !$0.isEmpty }.joined(separator: " ")
        return [name, c.email, c.phone].filter { !$0.isEmpty }.joined(separator: "\n")
    }

    private var divider: some View {
        Rectangle().fill(Fx.Color.line).frame(height: 1)
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .font(Fx.Font.footnote.weight(.semibold))
            .foregroundStyle(Fx.Color.inkSoft)
    }

    private func row(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: Fx.Space.xs) {
            label(title)
            Text(value)
                .font(Fx.Font.body)
                .foregroundStyle(Fx.Color.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Send

    @ViewBuilder
    private var sendSection: some View {
        let submission = model.submission
        if case .sending(let stage) = submission.phase {
            VStack(alignment: .leading, spacing: Fx.Space.s) {
                FxProgressSteps(current: stage.stepIndex, total: SubmissionStage.stepCount)
                Text(stage.label)
                    .font(Fx.Font.callout)
                    .foregroundStyle(Fx.Color.inkSoft)
            }
            .accessibilityElement(children: .combine)
        }
        if let error = submission.error {
            FxBanner(
                kind: .error,
                title: String(localized: "Not sent"),
                message: error.userMessage,
                actionTitle: String(localized: "Try again"),
                action: send
            )
            FxSecondaryButton(title: String(localized: "Send by e-mail instead"), systemImage: "envelope") {
                if MailComposer.canSendMail {
                    isMailPresented = true
                } else {
                    isSharePresented = true
                }
            }
            if !MailComposer.canSendMail {
                FxSecondaryButton(
                    title: copied ? String(localized: "Copied") : String(localized: "Copy report text"),
                    systemImage: copied ? "checkmark" : "doc.on.doc"
                ) {
                    UIPasteboard.general.string = mailText
                    copied = true
                }
                if let email = spec.fallbackEmail {
                    Text("Mail isn't set up on this phone. Share or copy the report and send it to \(email).")
                        .font(Fx.Font.footnote)
                        .foregroundStyle(Fx.Color.inkSoft)
                }
            }
        } else {
            FxPrimaryButton(
                title: String(localized: "Send to \(spec.municipality.name)"),
                systemImage: "paperplane",
                isLoading: submission.isSending,
                action: send
            )
        }
    }

    private func send() {
        Task { await model.send() }
    }

    private var mailText: String {
        var text = MailFallback.body(model.draft, spec: spec)
        if let email = spec.fallbackEmail {
            text = String(localized: "To: \(email)") + "\n" + String(localized: "Subject: \(MailFallback.subject(model.draft, spec: spec))") + "\n\n" + text
        }
        return text
    }

    private var shareItems: [Any] {
        var items: [Any] = [mailText]
        if let data = model.draft.photoJPEG, let image = UIImage(data: data) {
            items.append(image)
        }
        return items
    }
}
