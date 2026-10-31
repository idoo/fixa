import FixaKit
import UIKit

/// Seed content for `-FixaDemo 1`. Never touches the network or the saved history.
enum DemoData {
    static let coordinate = Coordinate(latitude: 59.3262, longitude: 18.3856)

    static var photo: UIImage? {
        guard let url = Bundle.main.url(forResource: "DemoPhoto", withExtension: "jpg"),
              let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }

    /// A filled-in profile, so Profile and the Report's reply row render with content.
    static let profile = Contact(firstName: "Anna", lastName: "Lind", phone: "070-123 45 67", email: "anna@example.se")

    static func draft(adapterID: String) -> ReportDraft {
        ReportDraft(
            adapterID: adapterID,
            tileID: "streetlight",
            categoryID: nil,
            description: String(localized: "The street light by the bus stop has been out since Monday. It is very dark there in the evening.", bundle: L10n.bundle, locale: L10n.locale),
            coordinate: coordinate,
            locationText: "Gustavsbergs centrum, Odelbergs väg",
            photoJPEG: nil,
            wantsFeedback: true,
            contact: profile
        )
    }

    /// The kommun's receipt as Abou words it (saved page `09-thankyou-receipt`), with the demo case number.
    static let kommunMessage = """
        Tack för att du använder vår e-tjänst!
        Här är ditt ärendenummer DEMO-1234
        Tack för din felanmälan!
        Med vänlig hälsning
        Värmdö kommun
        Om du har valt återkoppling kommer du att få svar inom 5 arbetsdagar. Om din fråga kräver längre handläggningstid bekräftar vi inom samma tid att vi tagit emot ditt ärende och talar också om vem som handlägger ditt ärende.
        """

    /// Built on access so the resident's text follows the in-app language.
    static var receipt: SentReport {
        let draft = draft(adapterID: AppModel.adapterID)
        return SentReport(
            caseNumber: "DEMO-1234",
            date: .now,
            isDryRun: false,
            kommunMessage: kommunMessage,
            residentText: draft.description,
            filedText: filedText(draft, swedish: "Gatlyktan vid busshållplatsen har varit släckt sedan måndag. Det är väldigt mörkt där på kvällen.")
        )
    }

    /// What the kommun gets for `draft`: the resident's text plus `swedish` as its translation
    /// (outside a Swedish UI), composed exactly as a real send.
    private static func filedText(_ draft: ReportDraft, swedish: String) -> String? {
        var filed = draft
        if L10n.effectiveLanguage != .sv {
            filed.translation = MachineTranslation(sourceLanguage: L10n.effectiveLanguage.rawValue, text: swedish)
        }
        return AdapterCatalog.shipped(id: AppModel.adapterID).map { ReportComposer.filedText(for: filed, spec: $0) }
    }

    static func historyItems(now: Date = .now) -> [HistoryItem] {
        let day: TimeInterval = 86_400
        let thumb = photo?.jpegData(compressionQuality: 0.8).flatMap { PhotoCollage.thumbnail(from: $0) }
        let streetlight = String(localized: "The street light by the bus stop has been out since Monday.", bundle: L10n.bundle, locale: L10n.locale)
        let filed = ReportDraft(
            adapterID: AppModel.adapterID, tileID: "streetlight", description: streetlight,
            coordinate: coordinate, locationText: "Gustavsbergs centrum, Odelbergs väg"
        )
        return [
            HistoryItem(
                id: UUID(), date: now.addingTimeInterval(-2 * day), tileID: "streetlight",
                description: streetlight,
                locationText: "Gustavsbergs centrum, Odelbergs väg",
                latitude: 59.3262, longitude: 18.3856, caseNumber: "DEMO-1234", thumbnail: thumb,
                filedText: filedText(filed, swedish: "Gatlyktan vid busshållplatsen har varit släckt sedan måndag."),
                kommunMessage: kommunMessage
            ),
            HistoryItem(
                id: UUID(), date: now.addingTimeInterval(-19 * day), tileID: "pothole",
                description: String(localized: "Deep pothole in the cycle lane, easy to miss in the dark.", bundle: L10n.bundle, locale: L10n.locale),
                locationText: "Värmdövägen, Hemmesta",
                latitude: 59.3229, longitude: 18.4978, caseNumber: "DEMO-1188", thumbnail: nil
            ),
            HistoryItem(
                id: UUID(), date: now.addingTimeInterval(-41 * day), tileID: "park",
                description: String(localized: "A swing at the playground is broken.", bundle: L10n.bundle, locale: L10n.locale),
                locationText: "Ekedal, Gustavsberg",
                latitude: 59.3301, longitude: 18.3792, caseNumber: nil, thumbnail: nil
            ),
        ]
    }
}
