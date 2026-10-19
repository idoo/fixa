import Foundation

/// An adapter that decodes but cannot be run, with the reasons.
public enum AdapterSpecError: Error, Sendable, Equatable {
    case invalid([String])
}

extension AdapterSpec {
    /// Consistency checks the JSON schema cannot express. Empty means the adapter can be run.
    public var problems: [String] {
        var problems: [String] = []
        func unique(_ ids: [String], _ what: String) {
            if Set(ids).count != ids.count { problems.append("duplicate \(what) id") }
            if ids.contains(where: \.isEmpty) { problems.append("empty \(what) id") }
        }
        if specVersion < 1 { problems.append("specVersion must be at least 1") }
        if let minAppBuild, minAppBuild < 1 { problems.append("minAppBuild must be at least 1") }
        if id.isEmpty { problems.append("empty id") }
        if channel.kind != "abou" { problems.append("unknown channel kind \(channel.kind)") }
        if URL(string: channel.baseURL)?.scheme != "https" { problems.append("baseURL must be https") }
        if channel.pages.isEmpty { problems.append("no pages") }
        unique(channel.pages.map(\.id), "page")
        let roles = Set(channel.pages.flatMap(\.fields).map(\.role))
        for role in [FieldSpec.Role.category, .description] where !roles.contains(role) {
            problems.append("no \(role.rawValue) field")
        }
        if let upload = channel.upload, !channel.pages.contains(where: { $0.id == upload.pageID }) {
            problems.append("upload page \(upload.pageID) is not a page")
        }
        if categories.isEmpty { problems.append("no categories") }
        if tiles.isEmpty { problems.append("no tiles") }
        unique(categories.map(\.id), "category")
        unique(tiles.map(\.id), "tile")
        for tile in tiles where category(id: tile.categoryID) == nil {
            problems.append("tile \(tile.id) has unknown category \(tile.categoryID)")
        }
        if validation.descriptionMin < 0 || validation.descriptionMin > validation.descriptionMax {
            problems.append("bad description length rules")
        }
        if let emergency {
            let contacts = Set(emergency.contacts.map(\.id))
            for id in [emergency.defaultContactID] + emergency.rules.map(\.contactID) where !contacts.contains(id) {
                problems.append("unknown emergency contact \(id)")
            }
        }
        return problems
    }
}

/// Whether a municipality's e-service works right now, published in `adapters/status.json`.
public struct AdapterStatus: Codable, Sendable, Equatable {
    public enum State: String, Codable, Sendable {
        case ok, degraded, down
    }

    public var state: State
    /// Kind words for the user, shown when `state != .ok`.
    public var message: LocalizedText?
    public var updated: Date?

    public init(state: State, message: LocalizedText? = nil, updated: Date? = nil) {
        self.state = state
        self.message = message
        self.updated = updated
    }

    public static let ok = AdapterStatus(state: .ok)

    /// Decodes `status.json`: adapter id → status. Dates are ISO 8601.
    public static func decodeMap(_ data: Data) throws -> [String: AdapterStatus] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([String: AdapterStatus].self, from: data)
    }
}

/// Decides whether a downloaded adapter may replace the one the app ships with.
public enum AdapterUpdatePolicy {
    /// Highest adapter `specVersion` this engine can run.
    public static let supportedSpecVersion = 1

    /// The remote adapter when it decodes, passes `AdapterSpec.problems`, has the bundled adapter's id,
    /// a supported `specVersion` and a `minAppBuild` this build meets; otherwise nil (keep the bundled one).
    public static func accept(remote: Data, bundled: AdapterSpec, appBuild: Int) -> AdapterSpec? {
        guard let spec = try? AdapterCatalog.decode(remote),
              spec.id == bundled.id,
              spec.specVersion <= supportedSpecVersion,
              (spec.minAppBuild ?? 0) <= appBuild
        else { return nil }
        return spec
    }
}
