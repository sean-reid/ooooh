import Foundation
import Session
import Speech
import Transcription

// transcribe <audio.wav> --script <script.json> --out <dir> [--locale en-US] [--speed 1] [--server]
//
// Runs the audio through SFSpeechRecognizer the way the phone's fallback engine does, on device
// with the dictation hint, and writes <out>/<name>.json (the recognizer's final segments and
// times) and <out>/<name>.labels.json (the script's labels moved to the recognized utterance
// that ends each labeled line). The merge and split report prints to stdout.
// --speed feeds the audio faster than real time; the pause timers run on the wall clock, so
// 1 is the faithful setting. --server uses Apple's servers instead of the on-device model.

let args = Array(CommandLine.arguments.dropFirst())

func option(_ name: String) -> String? {
  guard let index = args.firstIndex(of: name), index + 1 < args.count else { return nil }
  return args[index + 1]
}

func fail(_ message: String) -> Never {
  FileHandle.standardError.write(Data((message + "\n").utf8))
  exit(2)
}

func warn(_ message: String) {
  FileHandle.standardError.write(Data(("warning: " + message + "\n").utf8))
}

guard let audio = args.first, !audio.hasPrefix("--"), let scriptPath = option("--script"),
  let out = option("--out")
else {
  fail(
    "usage: transcribe <audio.wav> --script <script.json> --out <dir> [--locale en-US] [--speed 1] [--server]"
  )
}
let locale = Locale(identifier: option("--locale") ?? "en-US")
let speed = option("--speed").flatMap(Double.init) ?? 1
guard speed > 0 else { fail("--speed takes a number over 0") }

let script = try JSONDecoder().decode(
  Script.self, from: Data(contentsOf: URL(filePath: scriptPath)))

/// TCC answers on its own queue, so the continuation lives outside the main actor.
nonisolated func authorize() async -> SFSpeechRecognizerAuthorizationStatus {
  await withCheckedContinuation { continuation in
    SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
  }
}

let status = await authorize()
guard status == .authorized else {
  fail("speech recognition is not authorized for this process (status \(status.rawValue))")
}

var onDevice = !args.contains("--server")
if onDevice, !SpeechRecognizerTranscriber.supportsOnDeviceRecognition(locale: locale) {
  warn(
    "macOS has no on-device recognizer for \(locale.identifier); falling back to server recognition"
  )
  onDevice = false
}

let segments = try await SpeechRecognizerTranscriber.transcribe(
  file: URL(filePath: audio), locale: locale, onDevice: onDevice, speed: speed)
guard !segments.isEmpty else { fail("the recognizer heard nothing in \(audio)") }

let alignment = ScriptAlignment.align(script, to: segments)
let encoder = JSONEncoder()
encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
try FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
let fixturePath = "\(out)/\(script.name).json"
let labelsPath = "\(out)/\(script.name).labels.json"
try (encoder.encode(FixtureTranscriber.Fixture(segments: segments)) + Data("\n".utf8))
  .write(to: URL(filePath: fixturePath))
try (encoder.encode(alignment.labels) + Data("\n".utf8)).write(to: URL(filePath: labelsPath))

print("\(script.name): \(onDevice ? "on-device" : "server") recognition, \(locale.identifier)")
for line in alignment.report { print(line) }
print("wrote \(fixturePath)")
print("wrote \(labelsPath)")
