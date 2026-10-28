#if DEBUG
  import Design
  import SwiftUI

  struct RecordView: View {
    @State private var model = RecordModel()
    @Environment(\.dismiss) private var dismiss
    @ScaledMetric(relativeTo: .largeTitle) private var clockSize = 64

    var body: some View {
      ZStack {
        Palette.sky.ignoresSafeArea()
        VStack(alignment: .leading, spacing: 28) {
          header
          clock
          transcript
          Spacer(minLength: 0)
          control
        }
        .padding(24)
      }
    }

    private var header: some View {
      HStack(alignment: .firstTextBaseline) {
        Text("Record a fixture")
          .font(.system(.title2, design: .serif))
          .foregroundStyle(Palette.ink)
        Spacer()
        Button {
          dismiss()
        } label: {
          Text("Close").tapTarget()
        }
        .font(.body)
        .foregroundStyle(Palette.inkDim)
      }
    }

    private var clock: some View {
      TimelineView(.periodic(from: .now, by: 1)) { context in
        Text(elapsed(at: context.date))
          .font(.system(size: clockSize, weight: .light, design: .rounded))
          .monospacedDigit()
          .foregroundStyle(model.isRecording ? Palette.accent : Palette.ink)
          .accessibilityIdentifier("record.elapsed")
      }
    }

    private var transcript: some View {
      VStack(alignment: .leading, spacing: 12) {
        Text(model.volatileText.isEmpty ? placeholder : model.volatileText)
          .font(.body)
          .foregroundStyle(model.volatileText.isEmpty ? Palette.inkDim : Palette.ink)
          .fixedSize(horizontal: false, vertical: true)
          .frame(maxWidth: .infinity, minHeight: 88, alignment: .topLeading)
          .padding(16)
          .background(Palette.skyRaised, in: RoundedRectangle(cornerRadius: 16))
          .accessibilityIdentifier("record.volatile")
        Text("^[\(model.finalCount) final segment](inflect: true)")
          .font(.callout)
          .foregroundStyle(Palette.inkDim)
          .accessibilityIdentifier("record.finals")
        if case .failed(let message) = model.phase {
          Text(message)
            .font(.callout)
            .foregroundStyle(Palette.accent)
        }
        if model.phase == .finished, let fixture = model.files.first {
          finished(fixture)
        }
      }
    }

    private func finished(_ fixture: URL) -> some View {
      HStack(alignment: .firstTextBaseline) {
        VStack(alignment: .leading, spacing: 4) {
          Text(fixture.lastPathComponent)
            .font(.callout)
            .foregroundStyle(Palette.ink)
          if let engine = model.engine {
            Text(engine.title)
              .font(.footnote)
              .foregroundStyle(Palette.inkDim)
          }
        }
        Spacer()
        ShareLink(items: model.files) {
          Label("Share", systemImage: "square.and.arrow.up").tapTarget()
        }
        .font(.body)
        .foregroundStyle(Palette.accent)
        .accessibilityIdentifier("record.share")
      }
    }

    private var control: some View {
      Button(model.isRecording ? "Stop" : "Start") {
        Task { model.isRecording ? await model.stop() : await model.start() }
      }
      .buttonStyle(model.isRecording ? .amberOutlined : .amber)
      .disabled(!model.canStart && !model.isRecording)
      .accessibilityIdentifier(model.isRecording ? "record.stop" : "record.start")
    }

    private var placeholder: String {
      switch model.phase {
      case .idle, .finished, .failed: "Tap Start and think aloud."
      case .starting: "Starting the transcriber."
      case .recording: "Listening."
      case .stopping: "Finishing the transcript."
      }
    }

    private func elapsed(at now: Date) -> String {
      let seconds = Int(model.elapsed(at: now).rounded(.down))
      return "\(seconds / 60):" + String(format: "%02d", seconds % 60)
    }
  }

  #Preview {
    RecordView()
  }
#endif
