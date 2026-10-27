import Foundation
import SwiftData

@testable import Persistence

struct RowCounts: Equatable {
  var sessions: Int
  var segments: Int
  var lines: Int = 0
  var items: Int
  var threads: Int
}

extension SessionStore {
  func counts() throws -> RowCounts {
    RowCounts(
      sessions: try sessionCount(),
      segments: try modelContext.fetchCount(FetchDescriptor<StoredSegment>()),
      lines: try modelContext.fetchCount(FetchDescriptor<StoredLine>()),
      items: try modelContext.fetchCount(FetchDescriptor<StoredNoteItem>()),
      threads: try modelContext.fetchCount(FetchDescriptor<StoredThread>()))
  }
}
