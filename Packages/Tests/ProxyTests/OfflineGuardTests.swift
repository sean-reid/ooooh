import Foundation
import Governor
import Network
import Session
import State
import Testing

@testable import Proxy

@Suite struct OfflineGuardTests {
  let input = CheckInput(
    state: .empty, recentTranscript: [], signals: Signals(now: 0, pauseLength: 0, speechDensity: 1),
    checkIndex: 0)

  @Test func tripsAfterTwoFailuresAndResetsOnOneSuccess() async {
    let guardian = OfflineGuard()
    let changes = guardian.changes()
    guardian.recordFailure(URLError(.cannotConnectToHost))
    #expect(!guardian.isOffline)
    guardian.recordSuccess()
    guardian.recordFailure(URLError(.cannotConnectToHost))
    #expect(!guardian.isOffline)
    guardian.recordFailure(URLError(.timedOut))
    #expect(guardian.isOffline)
    guardian.recordFailure(URLError(.timedOut))
    guardian.recordSuccess()
    #expect(!guardian.isOffline)

    var seen: [Bool] = []
    for await change in changes {
      seen.append(change)
      if seen.count == 2 { break }
    }
    #expect(seen == [true, false])
  }

  @Test func cancellationIsNotAFailure() {
    let guardian = OfflineGuard()
    guardian.recordFailure(URLError(.cancelled))
    guardian.recordFailure(URLError(.cancelled))
    #expect(!guardian.isOffline)
  }

  @Test func allowsOneProbePerIntervalWhileOffline() {
    let guardian = OfflineGuard(retryInterval: 10, offline: true)
    let start = Date(timeIntervalSince1970: 1_000)
    #expect(guardian.allowsRequest(now: start))
    #expect(!guardian.allowsRequest(now: start.addingTimeInterval(5)))
    #expect(guardian.allowsRequest(now: start.addingTimeInterval(10)))
  }

  @Test func jevGoesQuietOnceTheWorkerIsUnreachable() async throws {
    let guardian = OfflineGuard()
    let client = ProxyClient(baseURL: URL(string: "http://127.0.0.1:9")!, offline: guardian)
    let jev = JevDecisionProvider(client: client)

    await #expect(throws: URLError.self) { try await jev.check(input) }
    #expect(!guardian.isOffline)
    let second = try await jev.check(input)
    #expect(second == .quiet)
    #expect(guardian.isOffline)
    let clock = ContinuousClock()
    var third = JevAnswers.quiet
    third.goodMoment = .init(1)
    let elapsed = try await clock.measure { third = try await jev.check(input) }
    #expect(third == .quiet)
    #expect(elapsed < .milliseconds(50))
  }

  @Test func oneGoodAnswerBringsTheWorkerBack() async throws {
    let url = try #require(
      Bundle.module.url(forResource: "decide", withExtension: "json", subdirectory: "Fixtures"))
    let server = try await OneShotHTTPServer(body: Data(contentsOf: url))
    let guardian = OfflineGuard(offline: true)
    let client = ProxyClient(
      baseURL: URL(string: "http://127.0.0.1:\(server.port)")!, offline: guardian)

    let answers = try await JevDecisionProvider(client: client).check(input)
    #expect(answers.goodMoment.probability == 0.82)
    #expect(!guardian.isOffline)
  }
}

/// Answers the first HTTP request on a kernel-picked port with one JSON body.
final class OneShotHTTPServer: Sendable {
  let port: UInt16
  private let listener: NWListener

  init(body: Data) async throws {
    let listener = try NWListener(using: .tcp, on: .any)
    self.listener = listener
    listener.newConnectionHandler = { connection in
      connection.start(queue: .global())
      connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { _, _, _, _ in
        let head = "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\n"
        let length = "Content-Length: \(body.count)\r\nConnection: close\r\n\r\n"
        connection.send(
          content: Data((head + length).utf8) + body,
          completion: .contentProcessed { _ in connection.cancel() })
      }
    }
    port = try await withCheckedThrowingContinuation { continuation in
      listener.stateUpdateHandler = { state in
        switch state {
        case .ready:
          listener.stateUpdateHandler = nil
          continuation.resume(returning: listener.port?.rawValue ?? 0)
        case .failed(let error):
          listener.stateUpdateHandler = nil
          continuation.resume(throwing: error)
        default: break
        }
      }
      listener.start(queue: .global())
    }
  }

  deinit { listener.cancel() }
}
