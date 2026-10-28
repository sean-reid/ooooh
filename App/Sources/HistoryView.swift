import Design
import Notes
import NotesUI
import Persistence
import SwiftUI

/// Past sessions, newest first. The search covers transcript and note text.
struct HistoryView: View {
  let store: SessionStore
  @State private var model: HistoryModel
  @State private var path: [UUID] = []
  @Environment(\.dismiss) private var dismiss
  @Environment(\.dynamicTypeSize) private var typeSize

  init(store: SessionStore) {
    self.store = store
    _model = State(initialValue: HistoryModel(store: store))
  }

  var body: some View {
    NavigationStack(path: $path) {
      ZStack {
        Palette.sky.ignoresSafeArea()
        VStack(spacing: 16) {
          header
          searchField
          if let failure = model.failure {
            Text(failure)
              .font(Typography.caption)
              .foregroundStyle(Palette.accent)
              .multilineTextAlignment(.center)
              .padding(.horizontal, 32)
              .accessibilityIdentifier("history.failure")
          }
          if model.loaded, model.rows.isEmpty {
            emptyLine
          } else {
            list
          }
        }
      }
      .toolbar(.hidden, for: .navigationBar)
      .navigationDestination(for: UUID.self) { id in
        StoredNotesScreen(store: store, sessionID: id)
          .toolbar(.hidden, for: .navigationBar)
      }
    }
    .tint(Palette.accent)
    .task { await model.load() }
    .task(id: model.query) { await model.search() }
    .onChange(of: path) { _, path in
      if path.isEmpty { Task { await model.search() } }
    }
  }

  private var header: some View {
    HStack(alignment: .firstTextBaseline) {
      Text("History")
        .font(Typography.title)
        .foregroundStyle(Palette.ink)
        .accessibilityAddTraits(.isHeader)
      Spacer()
      Button {
        dismiss()
      } label: {
        Text("Done").tapTarget()
      }
      .font(Typography.body)
      .foregroundStyle(Palette.inkDim)
      .accessibilityIdentifier("history.done")
    }
    .padding(.horizontal, 24)
    .padding(.top, 20)
  }

  /// The field wraps as the type grows; the placeholder shortens instead, since it cannot.
  private var searchField: some View {
    HStack(spacing: 8) {
      Image(systemName: "magnifyingglass")
        .foregroundStyle(Palette.inkDim)
      TextField(
        typeSize.isAccessibilitySize ? "Search" : "Search your sessions", text: $model.query,
        axis: .vertical
      )
      .lineLimit(1...3)
      .submitLabel(.search)
      .font(Typography.body)
      .foregroundStyle(Palette.ink)
      .textInputAutocapitalization(.never)
      .autocorrectionDisabled()
      .accessibilityIdentifier("history.search")
      if !model.query.isEmpty {
        Button {
          model.query = ""
        } label: {
          Image(systemName: "xmark.circle.fill")
            .foregroundStyle(Palette.inkDim)
            .tapTarget()
        }
        .accessibilityLabel("Clear the search")
      }
    }
    .padding(.horizontal, 16)
    .frame(minHeight: 44)
    .background(Palette.skyRaised, in: Capsule())
    .padding(.horizontal, 24)
  }

  private var emptyLine: some View {
    VStack {
      Spacer()
      Text(model.query.isEmpty ? "No sessions yet." : "Nothing matches.")
        .font(Typography.body)
        .foregroundStyle(Palette.inkDim)
        .accessibilityIdentifier("history.empty")
      Spacer()
    }
  }

  private var list: some View {
    List {
      ForEach(model.rows) { row in
        NavigationLink(value: row.id) {
          HistoryRow(summary: row)
        }
        .listRowBackground(Palette.sky)
        .listRowSeparatorTint(Palette.skyRaised)
        .onAppear {
          if row.id == model.rows.last?.id {
            Task { await model.loadMore() }
          }
        }
      }
      .onDelete { offsets in
        Task { await model.delete(at: offsets) }
      }
    }
    .listStyle(.plain)
    .scrollContentBackground(.hidden)
    .accessibilityIdentifier("history.list")
  }
}

struct HistoryRow: View {
  let summary: SessionSummary

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(title)
        .font(Typography.body)
        .foregroundStyle(summary.title.isEmpty ? Palette.inkDim : Palette.ink)
        .multilineTextAlignment(.leading)
      Text("\(date), \(duration), \(threads)")
        .font(Typography.caption)
        .foregroundStyle(Palette.inkDim)
    }
    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
    .padding(.vertical, 6)
    .accessibilityElement(children: .combine)
    .accessibilityLabel("\(title), \(date), \(duration), \(threads)")
  }

  private var title: String { summary.title.isEmpty ? "Untitled" : summary.title }

  private var date: String { summary.startedAt.formatted(date: .abbreviated, time: .shortened) }

  private var duration: String {
    Duration.seconds(summary.duration).formatted(
      .units(allowed: [.minutes, .seconds], width: .narrow))
  }

  private var threads: String {
    let count = summary.openThreadCount
    return count == 1 ? "1 open thread" : "\(count) open threads"
  }
}

/// One past session's notes, or its state when none were written.
struct StoredNotesScreen: View {
  let store: SessionStore
  let sessionID: UUID
  @State private var detail: SessionDetail?
  @State private var editor: NotesEditor?
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    ZStack {
      Palette.sky.ignoresSafeArea()
      if let editor {
        EditableNotesView(
          editor: editor, lines: detail?.lines ?? [], onMarkBad: markLine, onDone: { dismiss() })
      } else if let detail {
        PendingNotesView(
          state: detail.state ?? .empty, transcript: detail.transcript,
          line: PendingNotesView.noNotes, lines: detail.lines, onMarkBad: markLine,
          done: { dismiss() })
      }
    }
    .task {
      guard let detail = try? await store.detail(sessionID) else { return }
      editor = NotesEditor(store: store, detail: detail)
      self.detail = detail
    }
  }

  private func markLine(_ line: SpokenLine, bad: Bool) {
    Task { try? await store.markLine(line.id, bad: bad) }
  }
}

/// Pages of 50. A search waits for typing to pause, then fetches one page; the task that
/// started it is cancelled when the query changes, so a superseded result is dropped.
@MainActor @Observable
final class HistoryModel {
  static let page = 50
  static let debounce: Duration = .milliseconds(250)
  static let deleteFailedLine = "That session couldn't be deleted. It's still on this phone."

  let store: SessionStore
  var query = ""
  private(set) var rows: [SessionSummary] = []
  private(set) var loaded = false
  private(set) var failure: String?
  private var exhausted = false

  init(store: SessionStore) {
    self.store = store
  }

  func load() async {
    rows = (try? await store.sessions(limit: Self.page, offset: 0)) ?? []
    exhausted = rows.count < Self.page
    loaded = true
  }

  func loadMore() async {
    guard searching == nil, !exhausted else { return }
    let more = (try? await store.sessions(limit: Self.page, offset: rows.count)) ?? []
    rows += more
    exhausted = more.count < Self.page
  }

  func search() async {
    guard let needle = searching else {
      await load()
      return
    }
    guard (try? await Task.sleep(for: Self.debounce)) != nil else { return }
    guard let found = try? await store.search(needle, limit: Self.page), !Task.isCancelled else {
      return
    }
    rows = found
    exhausted = true
    loaded = true
  }

  /// Rows the store refuses to delete stay, under a line that says so.
  func delete(at offsets: IndexSet) async {
    failure = nil
    var deleted = IndexSet()
    for index in offsets {
      do {
        try await store.delete(session: rows[index].id)
        deleted.insert(index)
      } catch {
        failure = Self.deleteFailedLine
      }
    }
    rows.remove(atOffsets: deleted)
  }

  private var searching: String? {
    let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
    return needle.isEmpty ? nil : needle
  }
}
