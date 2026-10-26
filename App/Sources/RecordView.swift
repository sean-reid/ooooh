#if DEBUG
  import Design
  import SwiftUI

  struct RecordView: View {
    @State private var model = RecordModel()
    @State private var isSharing = false
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
      .onChange(of: model.phase) { _, phase in
        if phase == .finished { isSharing = true }
      }
      .sheet(isPresented: $isSharing) {
        ShareSheet(items: model.files)
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
      }
    }

    private var control: some View {
      Button {
        Task { model.isRecording ? await model.stop() : await model.start() }
      } label: {
        Text(model.isRecording ? "Stop" : "Start")
          .font(.headline)
          .frame(maxWidth: .infinity, minHeight: 56)
      }
      .buttonStyle(.plain)
      .foregroundStyle(model.isRecording ? Palette.ink : Palette.inkOnAmber)
      .background(model.isRecording ? Palette.skyRaised : Palette.amber, in: Capsule())
      .overlay(Capsule().strokeBorder(Palette.amberDim, lineWidth: model.isRecording ? 1 : 0))
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

  private struct ShareSheet: UIViewControllerRepresentable {
    let items: [URL]

    func makeUIViewController(context: Context) -> UIActivityViewController {
      UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
  }

  #Preview {
    RecordView()
  }
#endif
