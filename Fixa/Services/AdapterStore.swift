import Foundation
import Observation
import FixaKit
import os

/// The municipality adapter the app runs, updatable without an App Store release.
///
/// Starts from the copy cached by an earlier update (if this app build accepted it), else the bundled one.
/// Fixa contacts GitHub only when a send has just failed because the municipality's form changed:
/// `refreshAfterFormChange()` then fetches the adapter and `status.json`, each with its Ed25519 `.sig`, and
/// caches what `AdapterUpdatePolicy` and `AdapterStatus.decodeMap` accept (signature included). No periodic
/// or on-launch checks. A downloaded adapter may never change where reports go (`AdapterSpecValidator`).
/// Failures and rejections are only logged: the current adapter and status stay in place.
@MainActor @Observable
final class AdapterStore {
    private(set) var spec: AdapterSpec?
    private(set) var status: AdapterStatus = .ok

    @ObservationIgnored private let bundled: AdapterSpec?
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var isRefreshing = false

    nonisolated private static let remoteHost = "raw.githubusercontent.com"
    nonisolated private static let remoteBase = URL(string: "https://raw.githubusercontent.com/idoo/fixa/main/adapters/")!
    /// Floor between two checks, so repeated failures can't hammer GitHub.
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
        bundled = shipped.first { $0.id == adapterID } ?? shipped.first
        spec = bundled

        // A cache written by another build may predate the adapter this build ships: drop it.
        if defaults.integer(forKey: Self.cacheBuildKey) != Self.appBuild {
            defaults.removeObject(forKey: Self.lastCheckKey)
            try? FileManager.default.removeItem(at: Self.cacheDirectory)
            defaults.set(Self.appBuild, forKey: Self.cacheBuildKey)
        }
        if let bundled, let data = try? Data(contentsOf: Self.adapterCacheURL(bundled.id)) {
            do {
                let signature = try? Data(contentsOf: Self.signatureURL(Self.adapterCacheURL(bundled.id)))
                spec = try AdapterUpdatePolicy.check(remote: data, signature: signature, bundled: bundled, appBuild: Self.appBuild)
            } catch {
                Self.log.notice("Ignoring cached adapter: \(String(describing: error), privacy: .public)")
            }
        }
        if let id = spec?.id, let data = try? Data(contentsOf: Self.statusCacheURL),
           let map = try? AdapterStatus.decodeMap(data, signature: try? Data(contentsOf: Self.signatureURL(Self.statusCacheURL))) {
            status = map[id] ?? .ok
        }
    }

    /// Call only after a send failed because the form changed. Fetches the signed adapter and status
    /// (at most once per 15 minutes) and returns true when a different adapter was accepted, so the
    /// caller can retry that send once; the failed send stopped before the final step, so a retry is safe.
    @discardableResult
    func refreshAfterFormChange() async -> Bool {
        guard let bundled, !isRefreshing else { return false }
        if let last = defaults.object(forKey: Self.lastCheckKey) as? Date,
           Date.now.timeIntervalSince(last) < Self.minimumGap { return false }
        isRefreshing = true
        defer { isRefreshing = false }
        let before = spec

        let adapterFile = "\(bundled.id.replacingOccurrences(of: ".", with: "-")).json"
        async let adapterData = Self.fetch(adapterFile)
        async let adapterSignature = Self.fetch(adapterFile + ".sig")
        async let statusData = Self.fetch("status.json")
        async let statusSignature = Self.fetch("status.json.sig")
        let (remoteAdapter, remoteAdapterSignature) = await (adapterData, adapterSignature)
        let (remoteStatus, remoteStatusSignature) = await (statusData, statusSignature)
        guard remoteAdapter != nil || remoteStatus != nil else { return false }
        defaults.set(Date.now, forKey: Self.lastCheckKey)

        var changed = false
        if let remoteAdapter {
            do {
                let accepted = try AdapterUpdatePolicy.check(remote: remoteAdapter, signature: remoteAdapterSignature,
                                                             bundled: bundled, appBuild: Self.appBuild)
                let encoder = JSONEncoder()
                encoder.outputFormatting = .sortedKeys
                changed = (try? encoder.encode(accepted)) != (try? encoder.encode(before))
                spec = accepted
                Self.store(remoteAdapter, signature: remoteAdapterSignature, at: Self.adapterCacheURL(bundled.id))
            } catch {
                Self.log.error("Rejected downloaded adapter, keeping the current one: \(String(describing: error), privacy: .public)")
            }
        }
        if let remoteStatus {
            do {
                let map = try AdapterStatus.decodeMap(remoteStatus, signature: remoteStatusSignature)
                status = map[bundled.id] ?? .ok
                Self.store(remoteStatus, signature: remoteStatusSignature, at: Self.statusCacheURL)
            } catch {
                Self.log.error("Rejected downloaded status, keeping the current one: \(String(describing: error), privacy: .public)")
            }
        }
        return changed
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
