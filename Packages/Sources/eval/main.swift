import Foundation
import Governor
import Proxy
import Session
import Transcription

// eval <fixture.json> <labels.json> [--config c.json] [--answers a.jsonl]
// eval --corpus <dir> [--config c.json] [--answers-dir <dir>] [--require-perfect]
// eval --corpus <dir> --live <worker url> --record-dir <dir>
// Any form takes --arming-delay <seconds> to override the config's, 0 to speak at the decision.
//
// --live asks the real Jev through the Worker at every check, writes one JSON
// line per answer under --record-dir, and scores the run with the real floor.
// Each fixture opens its own session under an x-device label, so the Worker has
// to run with REQUIRE_ATTESTATION=false.
// Without answers the oracle runs with the floor off, so the loop and the scorer
// are checked against each other and a session must score 1.00 everywhere.

let args = Array(CommandLine.arguments.dropFirst())

func option(_ name: String) -> String? {
  guard let index = args.firstIndex(of: name), index + 1 < args.count else { return nil }
  return args[index + 1]
}

func fail(_ message: String) -> Never {
  FileHandle.standardError.write(Data((message + "\n").utf8))
  exit(2)
}

let decoder = JSONDecoder()

func load<T: Decodable>(_ type: T.Type, _ path: String) throws -> T {
  try decoder.decode(type, from: Data(contentsOf: URL(filePath: path)))
}

struct Run {
  var name: String
  var fixture: FixtureTranscriber.Fixture
  var labels: Labels
  var answers: String?
}

/// `decision` for `decision.fixture.json` and `decision.json` alike.
func runName(_ file: String) -> String {
  var name = URL(filePath: file).deletingPathExtension().lastPathComponent
  if name.hasSuffix(".fixture") { name = String(name.dropLast(".fixture".count)) }
  return name
}

/// Pairs every fixture in a directory with its labels file.
func corpus(in directory: String, answersDir: String?) throws -> [Run] {
  let files = try FileManager.default.contentsOfDirectory(atPath: directory)
  return try files.sorted().compactMap { file -> Run? in
    guard file.hasSuffix(".json"), !file.hasSuffix(".labels.json") else { return nil }
    let name = runName(file)
    let labelsPath = "\(directory)/\(name).labels.json"
    guard FileManager.default.fileExists(atPath: labelsPath) else { return nil }
    let answers = answersDir.map { "\($0)/\(name).jsonl" }
    return Run(
      name: name,
      fixture: try load(FixtureTranscriber.Fixture.self, "\(directory)/\(file)"),
      labels: try load(Labels.self, labelsPath),
      answers: answers.flatMap { FileManager.default.fileExists(atPath: $0) ? $0 : nil })
  }
}

let liveURL = option("--live").map { URL(string: $0)! }
let recordDir = option("--record-dir")

/// Sends the label as `x-device` with an empty assertion; only an unattested Worker accepts it.
struct LabelAttestor: Attestor {
  var label: String

  func assertion(clientDataHash: Data) async throws -> Assertion? {
    Assertion(keyId: label, assertion: Data())
  }

  func keyId() async throws -> String? { label }
}

/// Jev through the Worker, with the input tokens each answer cost added up.
actor LiveJev: DecisionProvider {
  let jev: JevDecisionProvider
  private(set) var tokens = 0
  private(set) var failures = 0

  init(client: ProxyClient) {
    jev = JevDecisionProvider(client: client)
  }

  /// A fixture replays faster than the Worker's per-device rate, so a 429 waits out its retryAfter.
  func check(_ input: CheckInput) async throws -> JevAnswers {
    var attempt = 0
    while true {
      do {
        let response = try await jev.decide(input)
        tokens += response.usage.jevInputTokens ?? 0
        return response.answers
      } catch ProxyError.status(429, let body) where attempt < 3 {
        attempt += 1
        let wait = retryAfter(in: body) ?? 10
        FileHandle.standardError.write(
          Data("  check \(input.checkIndex): rate limited, waiting \(wait) s\n".utf8))
        try await Task.sleep(for: .seconds(wait))
      } catch {
        failures += 1
        FileHandle.standardError.write(Data("  check \(input.checkIndex): \(error)\n".utf8))
        throw error
      }
    }
  }

  func retryAfter(in body: String) -> Double? {
    struct Refusal: Decodable {
      var retryAfter: Double
    }
    return (try? JSONDecoder().decode(Refusal.self, from: Data(body.utf8)))?.retryAfter
  }
}

var jevTokens = 0

struct Outcome {
  var report: EvalReport
  var checks: Int
  /// Checks in a pause, so nothing was said since the check before.
  var silent: Int
}

@MainActor func evaluate(_ run: Run, config base: GovernorConfig) async throws -> Outcome {
  var config = base
  let decisions: any DecisionProvider
  var recorder: RecordingDecisionProvider?
  var live: (client: ProxyClient, jev: LiveJev)?
  if let liveURL {
    guard let recordDir else { fail("--live needs --record-dir") }
    try FileManager.default.createDirectory(
      atPath: recordDir, withIntermediateDirectories: true)
    let label = "eval-\(run.name)-\(Int(Date().timeIntervalSince1970))"
    let client = ProxyClient(baseURL: liveURL, attestor: LabelAttestor(label: label))
    if case .refused(let reason) = try await client.startSession() {
      fail("\(run.name): the Worker refused a session, \(reason)")
    }
    let jev = LiveJev(client: client)
    let recording = try RecordingDecisionProvider(
      jev, writingTo: URL(filePath: "\(recordDir)/\(run.name).jsonl"))
    recorder = recording
    decisions = recording
    live = (client, jev)
  } else if let answers = run.answers {
    decisions = try RecordedDecisionProvider(contentsOf: URL(filePath: answers))
  } else {
    config.floor = .init(min: 0, max: 0)
    decisions = OracleDecisionProvider(labels: run.labels, config: config)
  }
  let result = await FixtureDriver.run(
    fixture: run.fixture, config: config,
    dependencies: .init(
      decisions: decisions, compactor: PassthroughCompactor(), phraser: TemplatePhraser()))
  if args.contains("--dump") {
    dump(run, result)
  }
  if let recorder, let live {
    try await recorder.close()
    try await live.client.endSession(minutes: (run.fixture.segments.last?.end ?? 0) / 60)
    let checks = await recorder.count
    let tokens = await live.jev.tokens
    let failures = await live.jev.failures
    jevTokens += tokens
    FileHandle.standardError.write(
      Data(
        "  \(run.name): \(checks) checks recorded, \(failures) failed, \(tokens) Jev input tokens\n"
          .utf8))
  }
  let ends = Set(result.transcript.map(\.end))
  let checks = result.records.compactMap {
    if case .check(let at, _, _, _) = $0 { at } else { nil }
  }
  return Outcome(
    report: EvalReport.score(result, against: run.labels), checks: checks.count,
    silent: checks.filter { !ends.contains($0) }.count)
}

/// One line per check: time, answers, and whether a label sits within one utterance before it.
func dump(_ run: Run, _ result: SessionResult) {
  let ends = result.transcript.map(\.end).sorted()
  func labeled(at: TimeInterval) -> String {
    for label in run.labels.labels where label.at <= at {
      let between = ends.filter { $0 > label.at && $0 <= at }.count
      if between <= EvalReport.tolerance { return label.kind }
    }
    return "-"
  }
  for record in result.records {
    guard case .check(let at, _, let a, let decision) = record else { continue }
    let line = String(
      format: "%@ %7.1f diff %.2f mom %.2f fin %.2f cmd %@ %.2f label %@ -> %@",
      run.name, at, a.articulationDifficulty.score, a.momentum.score,
      a.seemsFinished.probability, a.addressesApp.choice.rawValue, a.addressesApp.confidence,
      labeled(at: at), String(describing: decision))
    let cues = a.cues.sorted { $0.key < $1.key }
      .map { String(format: "%@=%.2f", $0.key, $0.value) }.joined(separator: " ")
    print(line + (cues.isEmpty ? "" : " cues " + cues))
  }
}

var config =
  try option("--config").map { try load(GovernorConfig.self, $0) } ?? .initial
if let delay = option("--arming-delay") {
  guard let seconds = TimeInterval(delay), seconds >= 0 else {
    fail("--arming-delay takes seconds, 0 or more")
  }
  config.armingDelay = seconds
}

var runs: [Run]
if let directory = option("--corpus") {
  runs = try corpus(in: directory, answersDir: option("--answers-dir"))
  guard !runs.isEmpty else { fail("no fixture and labels pairs in \(directory)") }
} else {
  guard args.count >= 2, !args[0].hasPrefix("--") else {
    fail("usage: eval <fixture.json> <labels.json> [--config c.json] [--answers a.jsonl]")
  }
  runs = [
    Run(
      name: runName(args[0]),
      fixture: try load(FixtureTranscriber.Fixture.self, args[0]),
      labels: try load(Labels.self, args[1]),
      answers: option("--answers"))
  ]
}

let mode =
  liveURL != nil
  ? "live Jev, real floor"
  : runs.allSatisfy { $0.answers == nil } ? "oracle, floor off" : "recorded answers"
print("config v\(config.version)  arming \(config.armingDelay) s  \(mode)")

var outcomes: [Outcome] = []
for run in runs {
  let outcome = try await evaluate(run, config: config)
  outcomes.append(outcome)
  if runs.count > 1 {
    let report = outcome.report
    let p = report.overall.precision.map { String(format: "%.2f", $0) } ?? "-"
    let r = report.overall.recall.map { String(format: "%.2f", $0) } ?? "-"
    let mark = report.isPerfect ? " " : "!"
    let name = run.name.padding(toLength: 20, withPad: " ", startingAt: 0)
    print("\(mark) \(name) p \(p)  r \(r)  checks \(outcome.checks)  silent \(outcome.silent)")
  }
}

let reports = outcomes.map(\.report)
let combined = EvalReport.merged(reports)
if runs.count > 1 { print("") }
print(combined.summary)
let checks = outcomes.reduce(0) { $0 + $1.checks }
let silent = outcomes.reduce(0) { $0 + $1.silent }
print("checks \(checks)  silent \(silent)  (\(checks == 0 ? 0 : silent * 100 / checks)%)")
if liveURL != nil { print("jev input tokens \(jevTokens)") }

if args.contains("--require-perfect"), !reports.allSatisfy(\.isPerfect) {
  fail("oracle did not score 1.00 on every session")
}
