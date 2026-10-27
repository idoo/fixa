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
  fixa-cli dry-run [--category ID ... | --all-categories] [--photo path.jpg] [--no-point] [--feedback yes|no] [--delay SECONDS]
      Fills every page with a TEST report and stops at the summary page. No case is created.
      --category may repeat; --all-categories runs once per adapter category, one after another,
      waiting --delay seconds (default 5) between runs. Without either, the street-light tile is used.
      Exit 2 if any run found the form changed, 1 if any run failed otherwise.
  fixa-cli submit --live --i-understand-this-creates-a-real-case [--photo path.jpg] [--save-html out.html]
      Creates a REAL case with the municipality.
"""

let args = Array(CommandLine.arguments.dropFirst())
guard let command = args.first, ["dry-run", "submit"].contains(command) else { fail(usage) }

guard let spec = AdapterCatalog.bundled().first(where: { $0.id == "se.varmdo.ksb" }) else {
    fail("Bundled adapter se.varmdo.ksb not found")
}

func values(after flag: String, in args: [String]) -> [String] {
    args.indices.filter { args[$0] == flag && $0 + 1 < args.count }.map { args[$0 + 1] }
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
}
if let path = value(after: "--photo", in: args) {
    guard let photo = FileManager.default.contents(atPath: path) else { fail("Cannot read \(path)") }
    draft.photoJPEG = photo
}
if dryRun {
    if args.contains("--no-point") { draft.coordinate = nil }
    switch value(after: "--feedback", in: args) {
    case nil: break
    case "yes": draft.wantsFeedback = true
    case "no": draft.wantsFeedback = false
    default: fail("--feedback takes yes or no\n\n" + usage)
    }
}

/// Category ids to run, in order; nil means the draft's tile.
var categories: [String?] = [nil]
if dryRun {
    let requested = args.contains("--all-categories") ? spec.categories.map(\.id) : values(after: "--category", in: args)
    for id in requested where spec.categories.first(where: { $0.id == id }) == nil {
        fail("Unknown category \(id). Known: \(spec.categories.map(\.id).joined(separator: ", "))")
    }
    if !requested.isEmpty { categories = requested }
}
let delay = Double(value(after: "--delay", in: args) ?? "5") ?? 5

print(dryRun ? "Dry run against \(spec.channel.baseURL) (stops at summary)" : "LIVE submission to \(spec.channel.baseURL)")

var worstExit: Int32 = 0
for (number, categoryID) in categories.enumerated() {
    if number > 0 { try await Task.sleep(for: .seconds(delay)) }
    var run = draft
    if let categoryID {
        run.tileID = nil
        run.categoryID = categoryID
    }
    let name = categoryID ?? "tile \(draft.tileID ?? "-")"
    print("== \(name): photo \(run.photoJPEG != nil ? "yes" : "no"), point \(run.coordinate != nil ? "yes" : "no"), feedback \(run.wantsFeedback ? "yes" : "no")")

    let issues = ReportValidator.validate(run, spec: spec)
    if !issues.isEmpty { fail("Draft invalid: \(issues)") }

    // A fresh transport (cookie jar) per run, like separate phones.
    let transport = RecordingTransport()
    let submitter = AbouSubmitter(spec: spec, transport: transport)
    do {
        let receipt = try await submitter.submit(run, dryRun: dryRun) { stage in
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
            print("\(name): reached the summary page. Nothing was submitted.")
        }
    } catch {
        if let path = value(after: "--save-html", in: args), let body = transport.lastBody {
            try? body.write(to: URL(fileURLWithPath: path))
        }
        switch error {
        case SubmissionError.formChanged(let drift):
            FileHandle.standardError.write(Data("FORM CHANGED (\(name)): \(drift.report) Update adapter \(spec.id) (key, labels or synonyms), then add a fixture test.\n".utf8))
            worstExit = 2
        case SubmissionError.uncertain(let detail):
            FileHandle.standardError.write(Data("UNCERTAIN (\(name)): the final confirmation was sent but no receipt was read. Do NOT resend; check with the municipality. \(detail)\n".utf8))
            if worstExit == 0 { worstExit = 1 }
        default:
            FileHandle.standardError.write(Data("Failed (\(name)): \(error)\n".utf8))
            if worstExit == 0 { worstExit = 1 }
        }
    }
}
exit(worstExit)
