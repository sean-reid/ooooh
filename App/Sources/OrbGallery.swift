import Design
import Proxy
import SwiftUI

#if DEBUG
  struct OrbGalleryButton: View {
    @State private var showsGallery = false

    var body: some View {
      Button {
        showsGallery = true
      } label: {
        Text("Gallery").tapTarget()
      }
      .font(Typography.caption)
      .foregroundStyle(Palette.inkDim)
      .sheet(isPresented: $showsGallery) { OrbGallery() }
    }
  }

  struct OrbGallery: View {
    @State private var phase = OrbPhase.resting
    @State private var level = 0.0
    @State private var cycling = false
    @State private var light = false
    @State private var speaking: Task<Void, Never>?

    var body: some View {
      ZStack {
        Palette.sky.ignoresSafeArea()
        VStack(spacing: 16) {
          Orb(level: level, phase: phase)
            .frame(maxWidth: 320)
          Text(phase.accessibilityLabel)
            .font(Typography.prompt)
            .foregroundStyle(Palette.ink)
          Picker("Phase", selection: $phase) {
            ForEach(OrbPhase.allCases, id: \.self) { Text($0.rawValue).tag($0) }
          }
          .pickerStyle(.segmented)
          HStack {
            Text("Level \(level, format: .number.precision(.fractionLength(2)))")
              .font(Typography.caption)
              .monospacedDigit()
            Slider(value: $level, in: 0...1)
          }
          Toggle("Cycle phases and level", isOn: $cycling)
          Toggle("Light", isOn: $light)
          Button {
            speakLine()
          } label: {
            Text("Speak a line through the Worker").tapTarget()
          }
          .disabled(WorkerURL.fromBundle == nil)
          .accessibilityIdentifier("gallery.speak")
        }
        .foregroundStyle(Palette.ink)
        .tint(Palette.accent)
        .font(Typography.body)
        .padding(24)
      }
      .preferredColorScheme(light ? .light : .dark)
      .onDisappear { speaking?.cancel() }
      .task(id: cycling) {
        guard cycling else { return }
        var tick = 0
        while !Task.isCancelled {
          try? await Task.sleep(for: .milliseconds(100))
          tick += 1
          level = 0.5 + 0.5 * sin(Double(tick) / 6)
          if tick % 40 == 0 {
            let all = OrbPhase.allCases
            phase = all[(all.firstIndex(of: phase)! + 1) % all.count]
          }
        }
      }
    }

    /// One fixed line through the real voice path; the orb follows the player's events.
    private func speakLine() {
      guard let url = WorkerURL.fromBundle else { return }
      let speaker = VoiceSpeaker(audio: ProxyClient(baseURL: url).speak)
      cycling = false
      phase = .aboutToSpeak
      speaking?.cancel()
      speaking = Task {
        for await event in speaker.speak(text: "Which part of that feels least clear?") {
          switch event {
          case .started: phase = .speaking
          case .finished: phase = .listening
          }
        }
      }
    }
  }
#else
  struct OrbGalleryButton: View {
    var body: some View { EmptyView() }
  }
#endif
