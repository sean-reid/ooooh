import Design
import SwiftUI

#if DEBUG
  struct OrbGalleryButton: View {
    @State private var showsGallery = false

    var body: some View {
      Button("Gallery") { showsGallery = true }
        .font(Typography.caption)
        .foregroundStyle(Palette.inkDim)
        .frame(minWidth: 44, minHeight: 44)

        .sheet(isPresented: $showsGallery) { OrbGallery() }
    }
  }

  struct OrbGallery: View {
    @State private var phase = OrbPhase.resting
    @State private var level = 0.0
    @State private var cycling = false
    @State private var light = false

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
        }
        .foregroundStyle(Palette.ink)
        .tint(Palette.accent)
        .font(Typography.body)
        .padding(24)
      }
      .preferredColorScheme(light ? .light : .dark)
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
  }
#else
  struct OrbGalleryButton: View {
    var body: some View { EmptyView() }
  }
#endif
