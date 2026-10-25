import Foundation

public struct ServerSentEvent: Equatable, Sendable {
  public var event: String
  public var data: String
}

/// Parses the `event:` and `data:` lines of a text/event-stream body. Blank lines end an event.
public enum ServerSentEvents {
  public static func events<Lines: AsyncSequence & Sendable>(from lines: Lines)
    -> AsyncThrowingStream<ServerSentEvent, Error> where Lines.Element == String
  {
    AsyncThrowingStream { continuation in
      let task = Task {
        do {
          var event = ""
          var data: [String] = []
          for try await line in lines {
            if line.isEmpty {
              if !data.isEmpty { continuation.yield(Self.make(event, data)) }
              event = ""
              data = []
            } else if let value = field("event", in: line) {
              event = value
            } else if let value = field("data", in: line) {
              data.append(value)
            }
          }
          if !data.isEmpty { continuation.yield(Self.make(event, data)) }
          continuation.finish()
        } catch {
          continuation.finish(throwing: error)
        }
      }
      continuation.onTermination = { _ in task.cancel() }
    }
  }

  static func make(_ event: String, _ data: [String]) -> ServerSentEvent {
    ServerSentEvent(event: event, data: data.joined(separator: "\n"))
  }

  static func field(_ name: String, in line: String) -> String? {
    guard line.hasPrefix("\(name):") else { return nil }
    let value = line.dropFirst(name.count + 1)
    return String(value.hasPrefix(" ") ? value.dropFirst() : value)
  }
}
