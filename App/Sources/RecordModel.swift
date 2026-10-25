#if DEBUG
  import AVFAudio
  import Audio
  import Foundation
  import Speech
  import Transcription

  enum RecordError: LocalizedError {
    case microphoneDenied, speechDenied

    var errorDescription: String? {
      switch self {
      case .microphoneDenied: "Microphone access was denied. Allow it in Settings and try again."
      case .speechDenied: "Speech recognition was denied. Allow it in Settings and try again."
      }
    }
  }

  @MainActor @Observable
  final class RecordModel {
    enum Phase: Equatable {
      case idle, starting, recording, stopping, finished
      case failed(String)
    }

    private(set) var phase: Phase = .idle
    private(set) var volatileText = ""
    private(set) var finalCount = 0
    private(set) var files: [URL] = []
    private(set) var startedAt: Date?
    private(set) var stoppedAt: Date?
    private var transcriber: SpeechAnalyzerTranscriber?
    private var recorder: FixtureRecorder?
    private var consumer: Task<Void, Never>?

    var isRecording: Bool { phase == .recording }

    func elapsed(at now: Date) -> TimeInterval {
      guard let startedAt else { return 0 }
      return (stoppedAt ?? now).timeIntervalSince(startedAt)
    }

    var canStart: Bool {
      switch phase {
      case .idle, .finished, .failed: true
      case .starting, .recording, .stopping: false
      }
    }

    func start() async {
      guard canStart else { return }
      phase = .starting
      volatileText = ""
      finalCount = 0
      files = []
      startedAt = nil
      stoppedAt = nil
      do {
        guard await AVAudioApplication.requestRecordPermission() else {
          throw RecordError.microphoneDenied
        }
        guard await Self.requestSpeechAuthorization() == .authorized else {
          throw RecordError.speechDenied
        }
        try AudioSessionController().activate()
        let recorder = try FixtureRecorder(directory: Self.fixturesDirectory)
        let transcriber = SpeechAnalyzerTranscriber(audioSink: recorder.audio)
        try await transcriber.start()
        self.recorder = recorder
        self.transcriber = transcriber
        startedAt = .now
        phase = .recording
        consumer = Task {
          for await event in transcriber.events() {
            await handle(event, recorder: recorder)
          }
        }
      } catch {
        phase = .failed(error.localizedDescription)
      }
    }

    func stop() async {
      guard isRecording, let transcriber, let recorder else { return }
      phase = .stopping
      stoppedAt = .now
      await transcriber.stop()
      await consumer?.value
      do {
        try await recorder.finish()
        files = [recorder.fixtureURL, recorder.audioURL]
        phase = .finished
      } catch {
        phase = .failed(error.localizedDescription)
      }
      try? AudioSessionController().deactivate()
    }

    private func handle(_ event: TranscriptEvent, recorder: FixtureRecorder) async {
      await recorder.record(event)
      guard case .segment(let segment) = event else { return }
      if segment.isFinal {
        finalCount += 1
        volatileText = ""
      } else {
        volatileText = segment.text
      }
    }

    static var fixturesDirectory: URL {
      URL.documentsDirectory.appending(path: "fixtures")
    }

    private static func requestSpeechAuthorization() async -> SFSpeechRecognizerAuthorizationStatus
    {
      await withCheckedContinuation { continuation in
        SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
      }
    }
  }
#endif
