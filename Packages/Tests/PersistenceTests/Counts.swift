import Foundation
import SwiftData

@testable import Persistence

struct RowCounts: Equatable {
  var sessions: Int
  var segments: Int
  var items: Int
  var threads: Int
}

extension SessionStore {
  func counts() throws -> RowCounts {
    RowCounts(
      sessions: try modelContext.fetchCount(FetchDescriptor<StoredSession>()),
      segments: try modelContext.fetchCount(FetchDescriptor<StoredSegment>()),
      items: try modelContext.fetchCount(FetchDescriptor<StoredNoteItem>()),
      threads: try modelContext.fetchCount(FetchDescriptor<StoredThread>()))
  }
}
