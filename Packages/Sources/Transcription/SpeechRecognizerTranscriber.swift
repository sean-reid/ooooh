import AVFAudio
import Foundation
import Speech

public enum SpeechRecognizerError: Error, Equatable, LocalizedError {
  case onDeviceUnsupported(Locale)
  case unavailable
  case noMicrophoneInput
  case stopped

  public var errorDescription: String? {
    switch self {
    case .onDeviceUnsupported(let locale):
      return "The speech recognizer cannot run \(locale.identifier) on this phone."
    case .unavailable:
      return "The speech recognizer is not available right now."
    case .noMicrophoneInput:
      return "No microphone input. Activate the audio session before starting."
    case .stopped:
      return "The speech recognizer stopped three requests in a row before hearing anything."
    }
  }
}

/// SFSpeechRecognizer as the engine touches it, so tests can stand in a fake.
protocol SpeechRecognizing: Sendable {
  var isAvailable: Bool { get }
  /// `handler` runs for every partial and final result, then once with an error when the request ends badly.
  func recognize(
    _ request: SFSpeechAudioBufferRecognitionRequest,
    handler: @escaping @Sendable (RecognitionResult?, (any Error)?) -> Void)
  func cancelAll()
}

extension SFSpeechAudioBufferRecognitionRequest: AudioAppending {}

/// Live transcription from the microphone through SFSpeechRecognizer on the phone. The recognizer
/// ends a request after a long silence and before one minute of audio, so each ending starts the
/// next request and the audio clock carries the times across them.
public actor SpeechRecognizerTranscriber: LiveTranscriber {
  public let locale: Locale
  public nonisolated let engine = TranscriptionEngine.speechRecognizer
  private let recognizer: any SpeechRecognizing
  private let audioSink: (any AudioBufferSink)?
  private let pause: TimeInterval
  private let onDevice: Bool
  private let clock: OffsetClock
  private let stream: AsyncStream<TranscriptEvent>
  private let continuation: AsyncStream<TranscriptEvent>.Continuation
  private let results: AsyncStream<Report>
  private let reports: AsyncStream<Report>.Continuation
  private let audioEngine = AVAudioEngine()
  nonisolated let feed: RequestFeed<SFSpeechAudioBufferRecognitionRequest>
  private var consumer: Task<Void, Never>?
  private var configurationWatch: Task<Void, Never>?
  private var silence: Task<Void, Never>?
  private var splitters: [Int: UtteranceSplitter] = [:]
  private var generation = 0
  private var heard = false
  private var emptyFailures = 0
  private var currentEnded = false
  private var activity = VoiceActivity()
  private var isRunning = false
  private var startedAt: ContinuousClock.Instant?
  private var heardResult = false

  private struct Report: Sendable {
    var generation: Int
    var result: RecognitionResult?
    var failed: Bool
  }

  public init(locale: Locale = .current, audioSink: (any AudioBufferSink)? = nil) {
    self.init(recognizer: LiveRecognizer(locale: locale), locale: locale, audioSink: audioSink)
  }

  /// `requestLimit` is the audio one request may hear before the next one takes over.
  init(
    recognizer: any SpeechRecognizing, locale: Locale, audioSink: (any AudioBufferSink)? = nil,
    requestLimit: TimeInterval = 50, pause: TimeInterval = 1, onDevice: Bool = true,
    clock: OffsetClock = OffsetClock(ContinuousClock())
  ) {
    self.recognizer = recognizer
    self.locale = locale
    self.audioSink = audioSink
    self.pause = pause
    self.onDevice = onDevice
    self.clock = clock
    self.feed = RequestFeed(limit: requestLimit)
    (stream, continuation) = AsyncStream.makeStream(of: TranscriptEvent.self)
    (results, reports) = AsyncStream.makeStream(of: Report.self)
  }

  public nonisolated func events() -> AsyncStream<TranscriptEvent> { stream }

  public nonisolated var audioTime: TimeInterval { feed.audioTime }

  /// The recognizer's model ships with iOS, so nothing downloads.
  public nonisolated func downloadProgress() -> AsyncStream<Double> {
    AsyncStream { $0.finish() }
  }

  public func start() async throws {
    guard !isRunning else { return }
    do {
      try beginRecognition()
      try installTap()
      try audioEngine.start()
      configurationWatch = watchConfiguration()
      log("started")
    } catch {
      log("start failed error=\(String(describing: error))", error: true)
      recognizer.cancelAll()
      consumer?.cancel()
      throw error
    }
  }

  /// Starts the first request and the result consumer without touching the microphone.
  func beginRecognition() throws {
    guard recognizer.isAvailable else { throw SpeechRecognizerError.unavailable }
    isRunning = true
    startedAt = .now
    consumer = Task { [weak self] in
      guard let self else { return }
      for await report in results {
        await self.handle(report)
      }
    }
    rotate()
  }

  public func stop() async {
    guard isRunning else { return }
    isRunning = false
    silence?.cancel()
    configurationWatch?.cancel()
    audioEngine.inputNode.removeTap(onBus: 0)
    audioEngine.stop()
    feed.swap(in: nil).previous?.endAudio()
    let deadline = clock.now() + .seconds(1.5)
    while !currentEnded, clock.now() < deadline {
      try? await clock.sleep(min(deadline, clock.now() + .milliseconds(100)))
    }
    recognizer.cancelAll()
    consumer?.cancel()
    finishStream()
  }

  private func installTap() throws {
    let node = audioEngine.inputNode
    let format = node.outputFormat(forBus: 0)
    log("input format=\(format.logDescription)")
    guard format.sampleRate > 0 else { throw SpeechRecognizerError.noMicrophoneInput }
    let sink = audioSink
    let feed = feed
    let monitor = TapMonitor(engine: engine)
    node.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
      monitor.observe(buffer)
      sink?.write(buffer)
      if feed.append(buffer) {
        Task { await self?.rotateAtLimit() }
      }
    }
    audioEngine.prepare()
  }

  func rotateAtLimit() {
    guard isRunning, feed.elapsedInRequest >= feed.limit else { return }
    rotate()
  }

  /// Ends the live request, so it reports its final result, and starts the next one.
  private func rotate() {
    generation += 1
    let generation = generation
    let request = SFSpeechAudioBufferRecognitionRequest()
    request.shouldReportPartialResults = true
    request.requiresOnDeviceRecognition = onDevice
    request.addsPunctuation = true
    request.taskHint = .dictation
    let (previous, start) = feed.swap(in: request)
    previous?.endAudio()
    splitters[generation] = UtteranceSplitter(offset: start, pause: pause)
    heard = false
    currentEnded = false
    log("request generation=\(generation) audioTime=\(Int(start))")
    let reports = reports
    recognizer.recognize(request) { result, error in
      if let error {
        let failure = error as NSError
        Self.log(
          "request failed generation=\(generation) domain=\(failure.domain) code=\(failure.code)",
          error: true)
      }
      reports.yield(Report(generation: generation, result: result, failed: error != nil))
    }
  }

  private func handle(_ report: Report) {
    guard splitters[report.generation] != nil else { return }
    let now = feed.audioTime
    if let result = report.result {
      if !heardResult, let startedAt {
        heardResult = true
        let latency = startedAt.duration(to: .now).wholeMilliseconds
        log("first result latencyMs=\(latency) final=\(result.isFinal)")
      }
      if report.generation == generation { heard = true }
      let segments = splitters[report.generation]?.segments(for: result, at: now) ?? []
      emit(segments)
      if report.generation == generation {
        if segments.last?.isFinal == false { scheduleFlush() } else { silence?.cancel() }
      }
    }
    if report.failed || report.result?.isFinal == true {
      requestEnded(report.generation, failed: report.failed)
    }
  }

  private func requestEnded(_ ended: Int, failed: Bool) {
    if let flushed = splitters[ended]?.flush(at: feed.audioTime) { emit([flushed]) }
    splitters[ended] = nil
    guard ended == generation else { return }
    silence?.cancel()
    currentEnded = true
    guard isRunning else { return }
    emptyFailures = failed && !heard ? emptyFailures + 1 : 0
    if emptyFailures >= 3 {
      fail(SpeechRecognizerError.stopped)
    } else {
      rotate()
    }
  }

  /// Finalizes the open utterance when no result follows it for `pause` seconds.
  private func scheduleFlush() {
    silence?.cancel()
    let generation = generation
    silence = Task { [weak self, pause, clock] in
      try? await clock.sleep(clock.now() + .seconds(pause))
      guard !Task.isCancelled else { return }
      await self?.flush(generation)
    }
  }

  private func flush(_ flushed: Int) {
    guard isRunning, flushed == generation else { return }
    if let segment = splitters[flushed]?.flush(at: feed.audioTime) { emit([segment]) }
  }

  private func emit(_ segments: [Segment]) {
    for segment in segments {
      for event in activity.events(for: segment) {
        continuation.yield(event)
      }
    }
  }

  private func fail(_ error: any Error) {
    guard isRunning else { return }
    isRunning = false
    silence?.cancel()
    configurationWatch?.cancel()
    audioEngine.inputNode.removeTap(onBus: 0)
    audioEngine.stop()
    recognizer.cancelAll()
    consumer?.cancel()
    finishStream()
  }

  /// The engine stops itself when the hardware format changes under it; that is the one way a
  /// started tap goes quiet without an error.
  private func watchConfiguration() -> Task<Void, Never> {
    Task { [weak self] in
      let changes = NotificationCenter.default.notifications(
        named: .AVAudioEngineConfigurationChange)
      for await _ in changes {
        await self?.logConfigurationChange()
      }
    }
  }

  private func logConfigurationChange() {
    log("engine configuration changed running=\(audioEngine.isRunning)")
  }

  private func finishStream() {
    for event in activity.close() {
      continuation.yield(event)
    }
    continuation.yield(.ended)
    continuation.finish()
    reports.finish()
  }

  private nonisolated func log(_ message: String, error: Bool = false) {
    Self.log(message, error: error)
  }

  private static func log(_ message: String, error: Bool = false) {
    if error {
      transcriptionLog.error("\(message, privacy: .public) engine=speechRecognizer")
    } else {
      transcriptionLog.info("\(message, privacy: .public) engine=speechRecognizer")
    }
  }
}

/// The real recognizer. Results arrive on their own serial queue and are reduced to plain values
/// before they cross into the actor.
final class LiveRecognizer: SpeechRecognizing, @unchecked Sendable {
  private let recognizer: SFSpeechRecognizer?
  private let lock = NSLock()
  private var tasks: [SFSpeechRecognitionTask] = []

  init(locale: Locale) {
    recognizer = SFSpeechRecognizer(locale: locale)
    let queue = OperationQueue()
    queue.maxConcurrentOperationCount = 1
    queue.name = "com.seanreid.ooooh.recognizer"
    recognizer?.queue = queue
  }

  var isAvailable: Bool { recognizer?.isAvailable ?? false }

  func recognize(
    _ request: SFSpeechAudioBufferRecognitionRequest,
    handler: @escaping @Sendable (RecognitionResult?, (any Error)?) -> Void
  ) {
    guard let recognizer else {
      handler(nil, SpeechRecognizerError.unavailable)
      return
    }
    let task = recognizer.recognitionTask(with: request) { result, error in
      handler(result.map(RecognitionResult.init), error)
    }
    lock.withLock { tasks.append(task) }
  }

  func cancelAll() {
    let tasks = lock.withLock {
      defer { self.tasks.removeAll() }
      return self.tasks
    }
    for task in tasks { task.cancel() }
  }
}

extension RecognitionResult {
  init(_ result: SFSpeechRecognitionResult) {
    self.init(
      words: result.bestTranscription.segments.map {
        RecognizedWord(text: $0.substring, timestamp: $0.timestamp, duration: $0.duration)
      }, isFinal: result.isFinal)
  }
}
