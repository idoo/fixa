import Foundation
import Observation
import FixaKit
import os

/// The municipality adapter the app runs, updatable without an App Store release.
///
/// Starts from the copy cached by an earlier refresh (if this app build accepted it), else the bundled one.
/// `refresh()` fetches the adapter and `status.json` from the repo at most every 6 hours (at once on the first
/// launch of a build) and caches what `AdapterUpdatePolicy` accepts for the next launch. A downloaded adapter
/// may never change where reports go (`AdapterSpecValidator`). Failures and rejections are only logged:
/// the current adapter and status stay in place.
@MainActor @Observable
final class AdapterStore {
    private(set) var spec: AdapterSpec?
    private(set) var status: AdapterStatus = .ok

    @ObservationIgnored private let bundled: AdapterSpec?
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var isRefreshing = false

    nonisolated private static let remoteHost = "raw.githubusercontent.com"
    nonisolated private static let remoteBase = URL(string: "https://raw.githubusercontent.com/idoo/fixa/main/adapters/")!
    private static let refreshInterval: TimeInterval = 6 * 60 * 60
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

        // A cache written by another build may predate the adapter this build ships: drop it and check now.
        if defaults.integer(forKey: Self.cacheBuildKey) != Self.appBuild {
            defaults.removeObject(forKey: Self.lastCheckKey)
            try? FileManager.default.removeItem(at: Self.cacheDirectory)
            defaults.set(Self.appBuild, forKey: Self.cacheBuildKey)
        }
        if let bundled, let data = try? Data(contentsOf: Self.adapterCacheURL(bundled.id)) {
            do {
                spec = try AdapterUpdatePolicy.check(remote: data, bundled: bundled, appBuild: Self.appBuild)
            } catch {
                Self.log.notice("Ignoring cached adapter: \(String(describing: error), privacy: .public)")
            }
        }
        if let id = spec?.id, let data = try? Data(contentsOf: Self.statusCacheURL),
           let map = try? AdapterStatus.decodeMap(data) {
            status = map[id] ?? .ok
        }
    }

    /// Fetches the remote adapter and status unless the last check was under 6 hours ago.
    func refresh() async {
        guard let bundled, !isRefreshing else { return }
        if let last = defaults.object(forKey: Self.lastCheckKey) as? Date,
           Date.now.timeIntervalSince(last) < Self.refreshInterval { return }
        isRefreshing = true
        defer { isRefreshing = false }

        async let adapterData = Self.fetch("\(bundled.id.replacingOccurrences(of: ".", with: "-")).json")
        async let statusData = Self.fetch("status.json")
        let (remoteAdapter, remoteStatus) = await (adapterData, statusData)
        guard remoteAdapter != nil || remoteStatus != nil else { return }
        defaults.set(Date.now, forKey: Self.lastCheckKey)

        if let remoteAdapter {
            do {
                spec = try AdapterUpdatePolicy.check(remote: remoteAdapter, bundled: bundled, appBuild: Self.appBuild)
                Self.store(remoteAdapter, at: Self.adapterCacheURL(bundled.id))
            } catch {
                Self.log.error("Rejected downloaded adapter, keeping the current one: \(String(describing: error), privacy: .public)")
            }
        }
        if let remoteStatus, let map = try? AdapterStatus.decodeMap(remoteStatus) {
            status = map[bundled.id] ?? .ok
            Self.store(remoteStatus, at: Self.statusCacheURL)
        }
    }

    // MARK: - Network and cache

    /// Downloads one file from the adapters folder of the repo. Nil unless it is a plain `name.json` file
    /// served with status 200 by raw.githubusercontent.com (also after redirects) and at most
    /// `AdapterSpecValidator.maxBytes` long.
    nonisolated private static func fetch(_ file: String) async -> Data? {
        guard file.range(of: #"^[a-z0-9-]+\.json$"#, options: .regularExpression) != nil else { return nil }
        let url = remoteBase.appendingPathComponent(file)
        guard url.scheme == "https", url.host == remoteHost, url.path.hasPrefix(remoteBase.path) else { return nil }
        let limit = AdapterSpecValidator.maxBytes
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

    private static func store(_ data: Data, at url: URL) {
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }
}
