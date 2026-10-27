import Foundation
import Testing
import XCTest

/// Polls until `condition` holds, and records a failure at the caller when `seconds` pass first.
/// Runs in the caller's isolation, so the condition reads actor state without hopping.
public func wait(
  for what: String = "the condition", seconds: Double = 10,
  isolation: isolated (any Actor)? = #isolation,
  sourceLocation: SourceLocation = #_sourceLocation, file: StaticString = #filePath,
  line: UInt = #line, _ condition: () async -> Bool
) async {
  let deadline = ContinuousClock.now + .seconds(seconds)
  while await !condition(), ContinuousClock.now < deadline {
    try? await Task.sleep(for: .milliseconds(10))
  }
  if await condition() { return }
  let message = "\(what) did not hold within \(seconds) s"
  if Test.current != nil {
    Issue.record(Comment(rawValue: message), sourceLocation: sourceLocation)
  } else {
    XCTFail(message, file: file, line: line)
  }
}
