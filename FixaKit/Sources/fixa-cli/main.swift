import CryptoKit
import Foundation
import FixaKit

/// Prints every request the dry run makes and keeps the last page, for `--save-html`.
final class LoggingTransport: HTTPTransport, @unchecked Sendable {
    private let base = URLSessionTransport.ephemeral()
    private let lock = NSLock()
    private var last: Data?

    var lastBody: Data? { lock.withLock { last } }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await base.send(request)
        print("  \(request.httpMethod ?? "GET") \(request.url?.absoluteString ?? "") -> \(response.statusCode) \(response.url?.absoluteString ?? "")")
        lock.withLock { last = data }
        return (data, response)
    }
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

func value(after flag: String, in args: [String]) -> String? {
    guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
    return args[i + 1]
}

let usage = """
usage:
  fixa-cli dry-run [--category ID ... | --all-categories] [--no-point] [--feedback yes|no] [--delay SECONDS] [--save-html out.html]
      Walks the LIVE e-service on the municipality's server up to the summary page with a sample
      report, without a photo, and stops there. No case is created, but the server sees the requests
      and keeps an unfinished session. Run it by hand only, after a user hit a changed form, to find
      what changed. Never in CI, never on a schedule.
      --category may repeat; --all-categories runs once per adapter category, one after another,
      waiting --delay seconds (default 5) between runs. Without either, the street-light tile is used.
      --save-html writes the last page reached. Exit 2 if any run found the form changed, 1 if any run failed otherwise.
  fixa-cli keygen [--key path]
      Creates the Ed25519 adapter signing key (default ~/.config/fixa/adapter-signing.key, mode 600)
      and prints its public key for AdapterSignature.publicKeyBase64. Never overwrites a key.
  fixa-cli sign <file> [--key path]
      Writes <file>.sig: the base64 Ed25519 signature of the file's exact bytes.
"""

let args = Array(CommandLine.arguments.dropFirst())

let keyPath = value(after: "--key", in: args)
    ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/fixa/adapter-signing.key").path

if args.first == "keygen" {
    let fm = FileManager.default
    guard !fm.fileExists(atPath: keyPath) else { fail("\(keyPath) already exists; refusing to overwrite a signing key") }
    let key = Curve25519.Signing.PrivateKey()
    let directory = (keyPath as NSString).deletingLastPathComponent
    do {
        try fm.createDirectory(atPath: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        guard fm.createFile(atPath: keyPath, contents: Data((key.rawRepresentation.base64EncodedString() + "\n").utf8),
                            attributes: [.posixPermissions: 0o600]) else { fail("Cannot write \(keyPath)") }
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: keyPath)
    } catch {
        fail("Cannot write \(keyPath): \(error)")
    }
    print("Private key: \(keyPath) (mode 600, never commit it)")
    print("Public key:  \(key.publicKey.rawRepresentation.base64EncodedString())")
    exit(0)
}

if args.first == "sign" {
    guard args.count >= 2, !args[1].hasPrefix("--") else { fail(usage) }
    let path = args[1]
    guard let text = try? String(contentsOfFile: keyPath, encoding: .utf8),
          let raw = Data(base64Encoded: text.trimmingCharacters(in: .whitespacesAndNewlines)),
          let key = try? Curve25519.Signing.PrivateKey(rawRepresentation: raw) else {
        fail("Cannot read signing key \(keyPath); run fixa-cli keygen first")
    }
    guard let bytes = FileManager.default.contents(atPath: path) else { fail("Cannot read \(path)") }
    do {
        let signature = try key.signature(for: bytes)
        try Data((signature.base64EncodedString() + "\n").utf8).write(to: URL(fileURLWithPath: path + ".sig"), options: .atomic)
    } catch {
        fail("Cannot sign \(path): \(error)")
    }
    let published = AdapterSignature.publicKeyBase64
    if key.publicKey.rawRepresentation.base64EncodedString() != published {
        FileHandle.standardError.write(Data("warning: this key is not the one the app trusts (\(published))\n".utf8))
    }
    print("Signed \(path) → \(path).sig")
    exit(0)
}

guard args.first == "dry-run" else { fail(usage) }

guard let spec = AdapterCatalog.bundled().first(where: { $0.id == "se.varmdo.ksb" }) else {
    fail("Bundled adapter se.varmdo.ksb not found")
}

func values(after flag: String, in args: [String]) -> [String] {
    args.indices.filter { args[$0] == flag && $0 + 1 < args.count }.map { args[$0 + 1] }
}

if args.contains("--photo") { fail("dry-run never uploads a photo\n\n" + usage) }

var draft = ReportDraft(
    adapterID: spec.id,
    tileID: "streetlight",
    description: "Kontroll av formuläret. Skickas inte in.",
    coordinate: Coordinate(latitude: 59.3262, longitude: 18.3856),
    locationText: "Gustavsbergs centrum",
    wantsFeedback: true,
    contact: Contact(email: "namn@example.se")
)

if args.contains("--no-point") { draft.coordinate = nil }
switch value(after: "--feedback", in: args) {
case nil: break
case "yes": draft.wantsFeedback = true
case "no": draft.wantsFeedback = false
default: fail("--feedback takes yes or no\n\n" + usage)
}

/// Category ids to run, in order; nil means the draft's tile.
var categories: [String?] = [nil]
let requested = args.contains("--all-categories") ? spec.categories.map(\.id) : values(after: "--category", in: args)
for id in requested where spec.categories.first(where: { $0.id == id }) == nil {
    fail("Unknown category \(id). Known: \(spec.categories.map(\.id).joined(separator: ", "))")
}
if !requested.isEmpty { categories = requested }
let delay = Double(value(after: "--delay", in: args) ?? "5") ?? 5

print("Dry run against the LIVE e-service \(spec.channel.baseURL) (stops at the summary page, no photo)")

var worstExit: Int32 = 0
for (number, categoryID) in categories.enumerated() {
    if number > 0 { try await Task.sleep(for: .seconds(delay)) }
    var run = draft
    if let categoryID {
        run.tileID = nil
        run.categoryID = categoryID
    }
    let name = categoryID ?? "tile \(draft.tileID ?? "-")"
    print("== \(name): point \(run.coordinate != nil ? "yes" : "no"), feedback \(run.wantsFeedback ? "yes" : "no")")

    let issues = ReportValidator.validate(run, spec: spec)
    if !issues.isEmpty { fail("Draft invalid: \(issues)") }

    // A fresh transport (cookie jar) per run, like separate phones.
    let transport = LoggingTransport()
    let submitter = AbouSubmitter(spec: spec, transport: transport)
    defer {
        if let path = value(after: "--save-html", in: args), let body = transport.lastBody {
            try? body.write(to: URL(fileURLWithPath: path))
            print("Saved the last page to \(path)")
        }
    }
    do {
        // A dry run stops at the summary page; the final send and its hook are never reached.
        _ = try await submitter.submit(run, dryRun: true, beforeFinalSend: {}) { stage in
            print("stage: \(stage)")
        }
        print("\(name): reached the summary page. Nothing was submitted.")
    } catch {
        switch error {
        case SubmissionError.formChanged(let drift):
            FileHandle.standardError.write(Data("FORM CHANGED (\(name)): \(drift.report) Update adapter \(spec.id) (key, labels or synonyms), then add a fixture test.\n".utf8))
            worstExit = 2
        case SubmissionError.blocked(let status):
            FileHandle.standardError.write(Data("BLOCKED (\(name)): the e-service answered \(status). Stopping; do not run again.\n".utf8))
            exit(1)
        default:
            FileHandle.standardError.write(Data("Failed (\(name)): \(error)\n".utf8))
            if worstExit == 0 { worstExit = 1 }
        }
    }
}
exit(worstExit)
