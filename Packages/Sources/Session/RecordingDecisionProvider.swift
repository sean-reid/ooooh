import Foundation
import Governor

/// Wraps a live provider and appends every answer as a JSON line, so a real run
/// can be scored again offline with `RecordedDecisionProvider`.
public actor RecordingDecisionProvider: DecisionProvider {
  let inner: any DecisionProvider
  let handle: FileHandle
  let encoder = JSONEncoder()
  public private(set) var count = 0

  public init(_ inner: any DecisionProvider, writingTo url: URL) throws {
    self.inner = inner
    FileManager.default.createFile(atPath: url.path, contents: nil)
    handle = try FileHandle(forWritingTo: url)
  }

  public func check(_ input: CheckInput) async throws -> JevAnswers {
    let answers = try await inner.check(input)
    let entry = RecordedDecisionProvider.Entry(checkIndex: input.checkIndex, answers: answers)
    var line = try encoder.encode(entry)
    line.append(0x0A)
    try handle.write(contentsOf: line)
    count += 1
    return answers
  }

  public func close() throws {
    try handle.close()
  }
}
