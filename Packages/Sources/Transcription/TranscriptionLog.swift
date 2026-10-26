import Foundation
import OSLog

/// Every line here names the engine and never carries transcript text.
let transcriptionLog = Logger(subsystem: "com.seanreid.ooooh", category: "transcription")

extension Duration {
  /// Whole milliseconds, for a latency on a log line.
  var wholeMilliseconds: Int64 {
    components.seconds * 1000 + components.attoseconds / 1_000_000_000_000_000
  }
}
