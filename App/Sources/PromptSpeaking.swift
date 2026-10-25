import Foundation

/// Says one prompt aloud and returns when it has finished.
protocol PromptSpeaking: Sendable {
  func speak(text: String) async
  func stop()
}

/// Says nothing, and takes about as long as reading the line would.
struct SilentSpeaker: PromptSpeaking {
  func speak(text: String) async {
    let words = text.split(separator: " ").count
    try? await Task.sleep(for: .seconds(max(1.5, Double(words) * 0.35)))
  }

  func stop() {}
}
