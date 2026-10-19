import Foundation
import Observation
import FixaKit

/// The municipality adapter the app runs, updatable without an App Store release.
///
/// Starts from the copy cached by an earlier refresh (if this app build accepted it), else the bundled one.
/// `refresh()` fetches the adapter and `status.json` from the repo at most every 6 hours (at once on the first
/// launch of a build) and caches what `AdapterUpdatePolicy` accepts for the next launch. Failures are silent:
/// the current adapter and status stay in place.
@MainActor @Observable
final class AdapterStore {
    private(set) var spec: AdapterSpec?
    private(set) var status: AdapterStatus = .ok

    @ObservationIgnored private let bundled: AdapterSpec?
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var isRefreshing = false

    private static let remoteBase = URL(string: "https://raw.githubusercontent.com/idoo/fixa/main/adapters/")!
    private static let refreshInterval: TimeInterval = 6 * 60 * 60
    private static let lastCheckKey = "adapterStore.lastCheck"
    private static let cacheBuildKey = "adapterStore.cacheBuild"

    private static let appBuild = Int(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "") ?? 0

    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
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
        if let bundled, let data = try? Data(contentsOf: Self.adapterCacheURL(bundled.id)),
           let cached = AdapterUpdatePolicy.accept(remote: data, bundled: bundled, appBuild: Self.appBuild) {
            spec = cached
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

        if let remoteAdapter,
           let accepted = AdapterUpdatePolicy.accept(remote: remoteAdapter, bundled: bundled, appBuild: Self.appBuild) {
            spec = accepted
            Self.store(remoteAdapter, at: Self.adapterCacheURL(bundled.id))
        }
        if let remoteStatus, let map = try? AdapterStatus.decodeMap(remoteStatus) {
            status = map[bundled.id] ?? .ok
            Self.store(remoteStatus, at: Self.statusCacheURL)
        }
    }

    // MARK: - Network and cache

    private static func fetch(_ file: String) async -> Data? {
        guard let (data, response) = try? await session.data(from: remoteBase.appendingPathComponent(file)),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return data
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
