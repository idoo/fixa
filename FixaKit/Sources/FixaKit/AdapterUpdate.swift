import CryptoKit
import Foundation

/// An adapter that cannot be run (`invalid`) or a downloaded one that may not replace the bundled one (`rejected`).
public enum AdapterSpecError: Error, Sendable, Equatable {
    case invalid([String])
    case rejected([String])
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
        problems += AdapterSpecValidator.channelProblems(channel)
        problems += AdapterSpecValidator.sizeProblems(self)
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

/// Ed25519 signatures on everything downloaded from `adapters/`. Each file `<name>` is published with
/// `<name>.sig`, the base64 signature of its exact bytes made by `fixa-cli sign`. The private key never
/// leaves the maintainer's Mac (`~/.config/fixa/adapter-signing.key`); the app only knows the public key.
public enum AdapterSignature {
    /// Raw 32-byte Ed25519 public key, base64. Replace only together with re-signing every adapter file.
    public static let publicKeyBase64 = "c3sHp2tuw15Z9OL8rQW+jQlKNfxKVnZe7c63/hqX3Bo="

    /// Largest `.sig` file accepted, in bytes (a signature is 88 base64 characters).
    public static let maxSignatureBytes = 256

    /// True when `signature` (the `.sig` file contents) is a valid signature of `data` by `publicKey`
    /// (raw key, base64). Nil, oversized, malformed or wrong signatures are false.
    public static func verify(_ data: Data, signature: Data?, publicKey: String = publicKeyBase64) -> Bool {
        guard let signature, signature.count <= maxSignatureBytes,
              let text = String(data: signature, encoding: .utf8),
              let raw = Data(base64Encoded: text.trimmingCharacters(in: .whitespacesAndNewlines)), raw.count == 64,
              let keyData = Data(base64Encoded: publicKey),
              let key = try? Curve25519.Signing.PublicKey(rawRepresentation: keyData) else { return false }
        return key.isValidSignature(raw, for: data)
    }
}

/// Whether a municipality's e-service works right now, published in `adapters/status.json`.
/// Only the state reaches the user, through the app's own strings: any other text in the file is ignored,
/// so a tampered or mistaken status file cannot put words on the screen.
public struct AdapterStatus: Codable, Sendable, Equatable {
    public enum State: String, Codable, Sendable {
        case ok, degraded, down
    }

    public var state: State
    public var updated: Date?

    public init(state: State, updated: Date? = nil) {
        self.state = state
        self.updated = updated
    }

    public static let ok = AdapterStatus(state: .ok)

    /// Decodes a signed `status.json`: adapter id → status. Dates are ISO 8601. Throws
    /// `AdapterSpecError.rejected` unless `signature` verifies against `publicKey`.
    public static func decodeMap(_ data: Data, signature: Data?, publicKey: String = AdapterSignature.publicKeyBase64) throws -> [String: AdapterStatus] {
        guard data.count <= AdapterSpecValidator.maxBytes else {
            throw AdapterSpecError.rejected(["status is \(data.count) bytes, over \(AdapterSpecValidator.maxBytes)"])
        }
        guard AdapterSignature.verify(data, signature: signature, publicKey: publicKey) else {
            throw AdapterSpecError.rejected(["status signature does not verify"])
        }
        return try decodeUnverifiedMap(data)
    }

    /// `decodeMap` without the signature check, for tests of the format only.
    static func decodeUnverifiedMap(_ data: Data) throws -> [String: AdapterStatus] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([String: AdapterStatus].self, from: data)
    }
}

/// Safety rules for adapters. The adapter decides where the user's name, e-mail, phone, photo and location
/// are posted, so a downloaded adapter may change how the form is filled but never where reports go.
public enum AdapterSpecValidator {
    /// Largest adapter download accepted, in bytes.
    public static let maxBytes = 256 * 1024
    public static let maxPages = 20
    public static let maxFieldsPerPage = 50
    public static let maxCategories = 100
    public static let maxTiles = 100
    /// Upper bound for labels or synonyms per entry and for emergency contacts and rules.
    public static let maxListItems = 50
    public static let maxCompletionPostBacks = 5

    /// Decodes a downloaded adapter and checks it against the bundled adapter with the same id.
    /// Throws `AdapterSpecError.rejected` for oversized data, unknown ids and any change of destination.
    public static func validateRemote(_ data: Data, bundled: [AdapterSpec]) throws -> AdapterSpec {
        guard data.count <= maxBytes else {
            throw AdapterSpecError.rejected(["download is \(data.count) bytes, over \(maxBytes)"])
        }
        let spec = try AdapterCatalog.decode(data)
        guard let pinned = bundled.first(where: { $0.id == spec.id }) else {
            throw AdapterSpecError.rejected(["unknown adapter id \(spec.id)"])
        }
        let problems = pinningProblems(remote: spec, bundled: pinned)
        guard problems.isEmpty else { throw AdapterSpecError.rejected(problems) }
        return spec
    }

    /// Everything a downloaded adapter may not change: where reports go (channel kind, host, service),
    /// the fallback e-mail address and the emergency phone numbers. Empty means the remote may be used.
    public static func pinningProblems(remote: AdapterSpec, bundled: AdapterSpec) -> [String] {
        var problems: [String] = []
        if remote.id != bundled.id { problems.append("unknown adapter id \(remote.id)") }
        if remote.channel.kind != bundled.channel.kind { problems.append("channel kind changed") }
        let remoteOrigin = origin(remote.channel.baseURL)
        if remoteOrigin == nil || remoteOrigin != origin(bundled.channel.baseURL) {
            problems.append("channel host changed")
        }
        if remote.channel.service != bundled.channel.service { problems.append("service changed") }
        if remote.fallbackEmail?.lowercased() != bundled.fallbackEmail?.lowercased() {
            problems.append("fallback e-mail changed")
        }
        let phones = { (spec: AdapterSpec) in (spec.emergency?.contacts.map(\.phone) ?? []).sorted() }
        if phones(remote) != phones(bundled) { problems.append("emergency phone numbers changed") }
        return problems
    }

    /// `https://host` with a plain ASCII host and no user, password, port, path, query or fragment.
    /// Returns the lowercased origin, or nil when the URL is anything else.
    static func origin(_ string: String) -> String? {
        guard !string.contains("\\"),
              let c = URLComponents(string: string),
              c.scheme?.lowercased() == "https",
              let host = c.host?.lowercased(), !host.isEmpty, !host.hasPrefix("."), !host.hasSuffix("."),
              host.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "." || $0 == "-") }),
              c.user == nil, c.password == nil, c.port == nil,
              c.path.isEmpty || c.path == "/", c.query == nil, c.fragment == nil
        else { return nil }
        return "https://\(host)"
    }

    /// A path the submitter may request: starts with one `/`, no scheme, `//`, backslash, whitespace or
    /// non-ASCII, and still resolves to `origin` (same scheme and host, no port or user).
    static func isSafePath(_ path: String, origin: String) -> Bool {
        guard path.hasPrefix("/"), !path.contains("//"), !path.contains(":"), !path.contains("\\"),
              path.unicodeScalars.allSatisfy({ $0.value > 0x20 && $0.value < 0x7F }),
              let base = URL(string: origin),
              let resolved = URL(string: path, relativeTo: base)?.absoluteURL,
              let resolvedOrigin = URL(string: "/", relativeTo: resolved)?.absoluteURL
        else { return false }
        return resolved.scheme == "https" && resolved.port == nil && resolved.user == nil
            && resolved.host?.lowercased() == base.host?.lowercased()
            && resolvedOrigin.absoluteString.lowercased() == origin + "/"
    }

    /// Channel rules every adapter must meet, bundled or downloaded.
    static func channelProblems(_ channel: AdapterSpec.Channel) -> [String] {
        guard let origin = origin(channel.baseURL) else {
            return ["baseURL must be a plain https origin (no user, port, path or query)"]
        }
        var problems: [String] = []
        var paths = [("introPath", channel.introPath), ("startPath", channel.startPath)]
        if let upload = channel.upload {
            paths += [("upload.path", upload.path), ("upload.actionPath", upload.actionPath)]
            // Both go into a multipart Content-Disposition header.
            for (name, value) in [("upload.filePartName", upload.filePartName), ("upload.fileName", upload.fileName)]
            where value.isEmpty || value.unicodeScalars.contains(where: { $0.value < 0x20 || $0.value == 0x7F || "\"\\/;".unicodeScalars.contains($0) }) {
                problems.append("\(name) has unsafe characters")
            }
        }
        for (name, path) in paths where !isSafePath(path, origin: origin) {
            problems.append("\(name) must be a path on \(origin)")
        }
        if let n = channel.maxCompletionPostBacks, !(0...maxCompletionPostBacks).contains(n) {
            problems.append("maxCompletionPostBacks must be 0...\(maxCompletionPostBacks)")
        }
        return problems
    }

    /// Upper bounds on list sizes, so an adapter cannot make the engine do absurd amounts of work.
    static func sizeProblems(_ spec: AdapterSpec) -> [String] {
        var problems: [String] = []
        let pages = spec.channel.pages
        if pages.count > maxPages { problems.append("more than \(maxPages) pages") }
        if pages.contains(where: { $0.fields.count > maxFieldsPerPage }) {
            problems.append("more than \(maxFieldsPerPage) fields on a page")
        }
        if spec.categories.count > maxCategories { problems.append("more than \(maxCategories) categories") }
        if spec.tiles.count > maxTiles { problems.append("more than \(maxTiles) tiles") }
        let fields = pages.flatMap(\.fields)
        var lists: [Int] = [spec.emergency?.contacts.count ?? 0, spec.emergency?.rules.count ?? 0]
        for field in fields {
            let labels: [String: [String]] = field.labels ?? [:]
            let synonyms: [String: [String]] = field.optionSynonyms ?? [:]
            lists.append(labels.count + synonyms.count)
            lists += labels.values.map(\.count)
            lists += synonyms.values.map(\.count)
        }
        lists += spec.categories.map { $0.synonyms?.count ?? 0 }
        if lists.contains(where: { $0 > maxListItems }) { problems.append("a list has more than \(maxListItems) items") }
        return problems
    }
}

/// Decides whether a downloaded adapter may replace the one the app ships with.
public enum AdapterUpdatePolicy {
    /// Highest adapter `specVersion` this engine can run.
    public static let supportedSpecVersion = 1

    /// The remote adapter when `signature` (its `.sig` file) verifies against `publicKey`, it passes
    /// `AdapterSpecValidator.validateRemote` against the bundled adapter (size, problems, same id, same
    /// destination), has a supported `specVersion` and a `minAppBuild` this build meets. Throws the reason
    /// otherwise; the caller keeps the bundled or last good adapter.
    public static func check(remote: Data, signature: Data?, bundled: AdapterSpec, appBuild: Int,
                             publicKey: String = AdapterSignature.publicKeyBase64) throws -> AdapterSpec {
        guard AdapterSignature.verify(remote, signature: signature, publicKey: publicKey) else {
            throw AdapterSpecError.rejected(["adapter signature does not verify"])
        }
        return try validate(remote: remote, bundled: bundled, appBuild: appBuild)
    }

    /// `check` without the reason: the accepted adapter, or nil (keep the bundled one).
    public static func accept(remote: Data, signature: Data?, bundled: AdapterSpec, appBuild: Int,
                              publicKey: String = AdapterSignature.publicKeyBase64) -> AdapterSpec? {
        try? check(remote: remote, signature: signature, bundled: bundled, appBuild: appBuild, publicKey: publicKey)
    }

    /// Every rule of `check` except the signature, so tests can exercise the content rules alone.
    static func validate(remote: Data, bundled: AdapterSpec, appBuild: Int) throws -> AdapterSpec {
        let spec = try AdapterSpecValidator.validateRemote(remote, bundled: [bundled])
        guard spec.specVersion <= supportedSpecVersion else {
            throw AdapterSpecError.rejected(["specVersion \(spec.specVersion) is newer than \(supportedSpecVersion)"])
        }
        if let minAppBuild = spec.minAppBuild, minAppBuild > appBuild {
            throw AdapterSpecError.rejected(["needs app build \(minAppBuild), this is \(appBuild)"])
        }
        return spec
    }
}
