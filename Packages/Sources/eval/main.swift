import Foundation
import Governor
import Session
import Transcription

// Usage: eval <fixture.json> <labels.json> [--config config.json] [--answers answers.jsonl]
// With no answers file the oracle provider runs, which should score perfectly.

let args = Array(CommandLine.arguments.dropFirst())
guard args.count >= 2 else {
  FileHandle.standardError.write(
    Data("usage: eval <fixture.json> <labels.json> [--config c.json] [--answers a.jsonl]\n".utf8))
  exit(2)
}

func option(_ name: String) -> String? {
  guard let index = args.firstIndex(of: name), index + 1 < args.count else { return nil }
  return args[index + 1]
}

let decoder = JSONDecoder()
let fixture = try decoder.decode(
  FixtureTranscriber.Fixture.self, from: Data(contentsOf: URL(filePath: args[0])))
let labels = try decoder.decode(Labels.self, from: Data(contentsOf: URL(filePath: args[1])))
let config =
  try option("--config").map {
    try decoder.decode(GovernorConfig.self, from: Data(contentsOf: URL(filePath: $0)))
  } ?? .initial
let decisions: any DecisionProvider =
  try option("--answers").map { try RecordedDecisionProvider(contentsOf: URL(filePath: $0)) }
  ?? OracleDecisionProvider(labels: labels)

let result = await FixtureDriver.run(
  fixture: fixture, config: config,
  dependencies: .init(
    decisions: decisions, compactor: PassthroughCompactor(), phraser: TemplatePhraser()))
let report = EvalReport.score(result, against: labels)
print(
  "config v\(config.version)  checks \(result.records.filter { if case .check = $0 { true } else { false } }.count)  prompts \(result.prompts.count)"
)
print(report.summary)
