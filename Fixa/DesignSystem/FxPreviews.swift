import SwiftUI

#if DEBUG
private struct FxCatalog: View {
    @State private var selected = "streetlight"
    @State private var email = ""
    @State private var text = ""
    @State private var wantsReply = true

    private let tiles: [(id: String, category: String, title: String, symbol: String)] = [
        ("streetlight", "lighting", "Street light out", "lightbulb.slash"),
        ("pothole", "roads", "Pothole or damaged road", "road.lanes"),
        ("water", "water", "Water or sewer", "drop"),
        ("other", "other", "Something else", "ellipsis.circle"),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Fx.Space.xl) {
                FxSectionHeader("Fixa", subtitle: "Report a problem in Värmdö in a minute.")
                FxProgressSteps(current: 2, total: 3)
                FxCallRow(title: "No water or a blocked sewer?",
                          detail: "\("08-454 25 71".ltrIsolated) · VA-jouren via SOS Alarm",
                          accessibilityValue: "08-454 25 71, VA-jouren via SOS Alarm", action: {})
                FxBanner(kind: .warning, title: "Outside Värmdö kommun",
                         message: "Move the pin if that's wrong.")
                FxTileGrid(columns: 2, spacing: Fx.Space.m) {
                    ForEach(tiles, id: \.id) { tile in
                        FxTile(title: tile.title, systemImage: tile.symbol, categoryID: tile.category,
                               isSelected: tile.id == selected) { selected = tile.id }
                    }
                }
                FxCard {
                    FxTextEditor(title: "Description", text: $text,
                                 prompt: "What is wrong? Write in any language.",
                                 issue: "Write at least 10 characters", minHeight: 120)
                    FxToggleRow(title: "I want a reply", subtitle: "The municipality e-mails you", isOn: $wantsReply)
                    FxTextField(title: "E-mail", text: $email, prompt: "name@example.com", kind: .email)
                }
                FxCard {
                    FxIconRow(systemImage: "chevron.left.forwardslash.chevron.right",
                              text: "Open source (EUPL-1.2) on GitHub",
                              link: URL(string: "https://github.com/idoo/fixa"))
                    FxIconRow(systemImage: "iphone", text: "No account, no server.")
                }
                FxBanner(kind: .info, title: "Sends to Värmdö kommun's e-service")
                FxBanner(kind: .error, title: "Could not send", message: "The server did not answer.",
                         actionTitle: "Try again", action: {})
                FxBanner(kind: .success, title: "Sent")
                FxStatusStamp(caseNumber: "DEMO-1234")
                    .frame(maxWidth: .infinity)
                FxPrimaryButton(title: "Send to Värmdö kommun", systemImage: "paperplane", action: {})
                FxPrimaryButton(title: "Sending…", isLoading: true, action: {})
                FxSecondaryButton(title: "Open the kommun's website", systemImage: "safari", action: {})
            }
            .padding(Fx.Space.l)
        }
        .fxScreenBackground()
    }
}

#Preview("Components · Light") {
    FxCatalog()
        .preferredColorScheme(.light)
}

#Preview("Components · Dark") {
    FxCatalog()
        .preferredColorScheme(.dark)
}

#Preview("Stamp · no number") {
    FxStatusStamp(caseNumber: nil)
        .padding()
        .fxScreenBackground()
}

#Preview("Components · AX5 Arabic") {
    FxCatalog()
        .environment(\.dynamicTypeSize, .accessibility3)
        .environment(\.layoutDirection, .rightToLeft)
}
#endif
