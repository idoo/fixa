import Foundation
import Observation
import FixaKit
import os

/// The municipality adapters the app runs, updatable without an App Store release.
///
/// Holds every bundled adapter: the primary one (Home's tile grid) and the other e-services ("More forms").
/// Each starts from the copy cached by an earlier update (if this app build accepted it), else the bundled one.
/// Fixa contacts GitHub only when a send has just failed because the municipality's form changed:
/// `refreshAfterFormChange(adapterID:)` then fetches that adapter and `status.json`, each with its Ed25519
/// `.sig`, and caches what `AdapterUpdatePolicy` and `AdapterStatus.decodeMap` accept (signature included).
/// No periodic or on-launch checks. A downloaded adapter may never change where reports go
/// (`AdapterSpecValidator`). Failures and rejections are only logged: the current adapter and status stay.
@MainActor @Observable
final class AdapterStore {
    /// Primary first, then the other e-services by `service.order`, then id.
    private(set) var specs: [AdapterSpec] = []
    /// The status file's map, by adapter id; a missing id is ok.
    private var statuses: [String: AdapterStatus] = [:]

    /// The primary adapter (KSB).
    var spec: AdapterSpec? { spec(id: primaryID) }

    @ObservationIgnored let primaryID: String
    @ObservationIgnored private let bundled: [String: AdapterSpec]
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var refreshing: Set<String> = []

    nonisolated private static let remoteHost = "raw.githubusercontent.com"
    nonisolated private static let remoteBase = URL(string: "https://raw.githubusercontent.com/idoo/fixa/main/adapters/")!
    /// Floor between two checks of one adapter, so repeated failures can't hammer GitHub.
    private static let minimumGap: TimeInterval = 15 * 60
    private static let lastCheckKey = "adapterStore.lastCheck"
    private static let cacheBuildKey = "adapterStore.cacheBuild"

    private static let appBuild = Int(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "") ?? 0
    nonisolated private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Fixa", category: "AdapterStore")

    /// No cookies, no cache, short timeouts: the download carries nothing about the user.
    nonisolated private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil
        config.httpCookieAcceptPolicy = .never
        config.httpShouldSetCookies = false
        config.urlCredentialStorage = nil
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 10
        return URLSession(configuration: config)
    }()

    init(adapterID: String, defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let shipped = AdapterCatalog.bundled()
        primaryID = shipped.contains { $0.id == adapterID } ? adapterID : (shipped.first?.id ?? adapterID)
        bundled = Dictionary(shipped.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        // A cache written by another build may predate the adapters this build ships: drop it.
        if defaults.integer(forKey: Self.cacheBuildKey) != Self.appBuild {
            for id in bundled.keys {
                defaults.removeObject(forKey: Self.lastCheckKey(id, primary: id == primaryID))
            }
            try? FileManager.default.removeItem(at: Self.cacheDirectory)
            defaults.set(Self.appBuild, forKey: Self.cacheBuildKey)
        }
        var loaded: [AdapterSpec] = []
        for original in shipped where loaded.allSatisfy({ $0.id != original.id }) {
            var current = original
            if let data = try? Data(contentsOf: Self.adapterCacheURL(original.id)) {
                do {
                    let signature = try? Data(contentsOf: Self.signatureURL(Self.adapterCacheURL(original.id)))
                    current = try AdapterUpdatePolicy.check(remote: data, signature: signature, bundled: original, appBuild: Self.appBuild)
                } catch {
                    Self.log.notice("Ignoring cached adapter \(original.id, privacy: .public): \(String(describing: error), privacy: .public)")
                }
            }
            loaded.append(current)
        }
        specs = Self.ordered(loaded, primaryID: primaryID)
        if let data = try? Data(contentsOf: Self.statusCacheURL),
           let map = try? AdapterStatus.decodeMap(data, signature: try? Data(contentsOf: Self.signatureURL(Self.statusCacheURL))) {
            statuses = map
        }
    }

    func spec(id: String) -> AdapterSpec? {
        specs.first { $0.id == id }
    }

    func status(id: String) -> AdapterStatus {
        statuses[id] ?? .ok
    }

    /// Call only after a send failed because the form changed. Fetches the signed adapter and status
    /// (at most once per 15 minutes per adapter) and returns true when a different adapter was accepted,
    /// so the caller can retry that send once; the failed send stopped before the final step, so a retry is safe.
    @discardableResult
    func refreshAfterFormChange(adapterID: String) async -> Bool {
        guard let original = bundled[adapterID], !refreshing.contains(adapterID) else { return false }
        let checkKey = Self.lastCheckKey(adapterID, primary: adapterID == primaryID)
        if let last = defaults.object(forKey: checkKey) as? Date,
           Date.now.timeIntervalSince(last) < Self.minimumGap { return false }
        refreshing.insert(adapterID)
        defer { refreshing.remove(adapterID) }
        let before = spec(id: adapterID)

        let adapterFile = "\(adapterID.replacingOccurrences(of: ".", with: "-")).json"
        async let adapterData = Self.fetch(adapterFile)
        async let adapterSignature = Self.fetch(adapterFile + ".sig")
        async let statusData = Self.fetch("status.json")
        async let statusSignature = Self.fetch("status.json.sig")
        let (remoteAdapter, remoteAdapterSignature) = await (adapterData, adapterSignature)
        let (remoteStatus, remoteStatusSignature) = await (statusData, statusSignature)
        guard remoteAdapter != nil || remoteStatus != nil else { return false }
        defaults.set(Date.now, forKey: checkKey)

        var changed = false
        if let remoteAdapter {
            do {
                let accepted = try AdapterUpdatePolicy.check(remote: remoteAdapter, signature: remoteAdapterSignature,
                                                             bundled: original, appBuild: Self.appBuild)
                let encoder = JSONEncoder()
                encoder.outputFormatting = .sortedKeys
                changed = (try? encoder.encode(accepted)) != (try? encoder.encode(before))
                specs = Self.ordered(specs.filter { $0.id != adapterID } + [accepted], primaryID: primaryID)
                Self.store(remoteAdapter, signature: remoteAdapterSignature, at: Self.adapterCacheURL(adapterID))
            } catch {
                Self.log.error("Rejected downloaded adapter \(adapterID, privacy: .public), keeping the current one: \(String(describing: error), privacy: .public)")
            }
        }
        if let remoteStatus {
            do {
                statuses = try AdapterStatus.decodeMap(remoteStatus, signature: remoteStatusSignature)
                Self.store(remoteStatus, signature: remoteStatusSignature, at: Self.statusCacheURL)
            } catch {
                Self.log.error("Rejected downloaded status, keeping the current one: \(String(describing: error), privacy: .public)")
            }
        }
        return changed
    }

    /// Primary first, then adapters with a `service` by its order, then the rest; ties by id.
    private static func ordered(_ specs: [AdapterSpec], primaryID: String) -> [AdapterSpec] {
        specs.sorted { lhs, rhs in
            let left = (lhs.id == primaryID ? 0 : 1, lhs.service?.order ?? Int.max)
            let right = (rhs.id == primaryID ? 0 : 1, rhs.service?.order ?? Int.max)
            return left != right ? left < right : lhs.id < rhs.id
        }
    }

    /// The primary keeps the key earlier builds wrote.
    private static func lastCheckKey(_ id: String, primary: Bool) -> String {
        primary ? lastCheckKey : "\(lastCheckKey).\(id)"
    }

    // MARK: - Network and cache

    /// Downloads one file from the adapters folder of the repo. Nil unless it is a plain `name.json` or
    /// `name.json.sig` file served with status 200 by raw.githubusercontent.com (also after redirects) and at
    /// most `AdapterSpecValidator.maxBytes` (`AdapterSignature.maxSignatureBytes` for a `.sig`) long.
    nonisolated private static func fetch(_ file: String) async -> Data? {
        guard file.range(of: #"^[a-z0-9-]+\.json(\.sig)?$"#, options: .regularExpression) != nil else { return nil }
        let url = remoteBase.appendingPathComponent(file)
        guard url.scheme == "https", url.host == remoteHost, url.path.hasPrefix(remoteBase.path) else { return nil }
        let limit = file.hasSuffix(".sig") ? AdapterSignature.maxSignatureBytes : AdapterSpecValidator.maxBytes
        do {
            let (bytes, response) = try await session.bytes(from: url)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                  http.url?.scheme == "https", http.url?.host == remoteHost,
                  http.expectedContentLength <= Int64(limit) else {
                log.error("Refused adapter download \(file, privacy: .public)")
                return nil
            }
            var data = Data()
            for try await byte in bytes {
                data.append(byte)
                if data.count > limit {
                    log.error("Adapter download \(file, privacy: .public) is over \(limit) bytes")
                    return nil
                }
            }
            return data
        } catch {
            return nil
        }
    }

    private static var cacheDirectory: URL {
        URL.applicationSupportDirectory.appendingPathComponent("Adapters", isDirectory: true)
    }

    private static func adapterCacheURL(_ id: String) -> URL {
        cacheDirectory.appendingPathComponent("\(id).json")
    }

    private static var statusCacheURL: URL {
        cacheDirectory.appendingPathComponent("status.json")
    }

    private static func signatureURL(_ url: URL) -> URL {
        url.appendingPathExtension("sig")
    }

    /// Caches a verified file with its signature, so the next launch verifies it again.
    private static func store(_ data: Data, signature: Data?, at url: URL) {
        guard let signature else { return }
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
        try? signature.write(to: signatureURL(url), options: .atomic)
    }
}
