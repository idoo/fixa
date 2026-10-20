import Foundation
import FixaKit

/// Saves every response body to Caches/fixa-responses/NN-<page>.html.
/// Used only with the `-FixaLiveTest 1` launch hook, so the real receipt page can be inspected.
nonisolated struct RecordingTransport: HTTPTransport {
    let base: URLSessionTransport
    let directory: URL
    private let counter = Counter()

    init(base: URLSessionTransport = .ephemeral()) {
        self.base = base
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        directory = caches.appending(path: "fixa-responses", directoryHint: .isDirectory)
        try? FileManager.default.removeItem(at: directory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await base.send(request)
        let index = counter.next()
        let page = response.url.flatMap { AbouPageParser.pageID(from: $0) } ?? response.url?.lastPathComponent ?? "response"
        let name = String(format: "%02d-%@.html", index, page.replacingOccurrences(of: "/", with: "_"))
        // Response pages can echo the reporter's name and e-mail.
        try? data.write(to: directory.appending(path: name), options: .completeFileProtection)
        return (data, response)
    }
}

private nonisolated final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    func next() -> Int {
        lock.lock(); defer { lock.unlock() }
        value += 1
        return value
    }
}
