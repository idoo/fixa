import Foundation
import FixaKit

/// Keeps the last response so `submit` can save the final HTML.
final class RecordingTransport: HTTPTransport, @unchecked Sendable {
    private let base = URLSessionTransport.ephemeral()
    private let lock = NSLock()
    private var last: (Data, URL?)?

    var lastBody: Data? { lock.withLock { last?.0 } }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await base.send(request)
        print("  \(request.httpMethod ?? "GET") \(request.url?.absoluteString ?? "") -> \(response.statusCode) \(response.url?.absoluteString ?? "")")
        lock.withLock { last = (data, response.url) }
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
  fixa-cli dry-run
      Fills every page with a TEST report and stops at the summary page. No case is created.
  fixa-cli submit --live --i-understand-this-creates-a-real-case [--photo path.jpg] [--save-html out.html]
      Creates a REAL case with the municipality.
"""

let args = Array(CommandLine.arguments.dropFirst())
guard let command = args.first, ["dry-run", "submit"].contains(command) else { fail(usage) }

guard let spec = AdapterCatalog.bundled().first(where: { $0.id == "se.varmdo.ksb" }) else {
    fail("Bundled adapter se.varmdo.ksb not found")
}

var draft = ReportDraft(
    adapterID: spec.id,
    tileID: "streetlight",
    description: "TEST — ignorera, testinlämning från app-utveckling. Gatlampan lyser inte.",
    coordinate: Coordinate(latitude: 59.3262, longitude: 18.3856),
    locationText: "Gustavsbergs centrum",
    wantsFeedback: true,
    contact: Contact(email: "test@test.se")
)

let dryRun = command == "dry-run"
if !dryRun {
    guard args.contains("--live"), args.contains("--i-understand-this-creates-a-real-case") else {
        fail("submit needs --live --i-understand-this-creates-a-real-case\n\n" + usage)
    }
    if let path = value(after: "--photo", in: args) {
        guard let photo = FileManager.default.contents(atPath: path) else { fail("Cannot read \(path)") }
        draft.photoJPEG = photo
    }
}

let issues = ReportValidator.validate(draft, spec: spec)
if !issues.isEmpty { fail("Draft invalid: \(issues)") }

let transport = RecordingTransport()
let submitter = AbouSubmitter(spec: spec, transport: transport)
print(dryRun ? "Dry run against \(spec.channel.baseURL) (stops at summary)" : "LIVE submission to \(spec.channel.baseURL)")

do {
    let receipt = try await submitter.submit(draft, dryRun: dryRun) { stage in
        print("stage: \(stage)")
    }
    if let path = value(after: "--save-html", in: args), let body = transport.lastBody {
        try body.write(to: URL(fileURLWithPath: path))
        print("Saved final HTML to \(path)")
    }
    if let receipt {
        print("Receipt:")
        print("  case number: \(receipt.caseNumber ?? "(none found)")")
        print("  final URL:   \(receipt.finalURL.absoluteString)")
        print("  title:       \(receipt.title)")
        print("  message:     \(receipt.message.prefix(500))")
    } else {
        print("Reached the summary page. Nothing was submitted.")
    }
} catch {
    if let path = value(after: "--save-html", in: args), let body = transport.lastBody {
        try? body.write(to: URL(fileURLWithPath: path))
    }
    fail("Failed: \(error)")
}
