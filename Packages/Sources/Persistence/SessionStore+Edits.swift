import Foundation
import Notes
import SwiftData

extension SessionStore {
  /// Changes the text or the resolved mark and flags the item as edited.
  public func editItem(_ itemID: UUID, text: String? = nil, resolved: Bool? = nil) throws {
    let item = try item(itemID)
    if let text {
      item.text = text
    }
    if let resolved {
      item.resolved = resolved
    }
    item.edited = true
    if let thread = thread(for: item) {
      thread.text = item.text
      thread.resolved = item.resolved
      thread.resolvedAt = item.resolved ? (thread.resolvedAt ?? .now) : nil
      if !item.resolved { thread.resolvedIn = nil }
      if let session = item.session { try refreshOpenThreadCount(session) }
    }
    try modelContext.save()
  }

  public func deleteItem(_ itemID: UUID) throws {
    let item = try item(itemID)
    let session = item.session
    if let thread = thread(for: item) {
      modelContext.delete(thread)
    }
    modelContext.delete(item)
    if let session { try refreshOpenThreadCount(session) }
    try modelContext.save()
  }

  /// Appends an item to a section and returns its handle.
  @discardableResult
  public func addItem(_ text: String, section: NoteSection, to sessionID: UUID) throws -> UUID {
    let session = try session(sessionID)
    let order = ((session.items ?? []).map(\.order).max() ?? 0) + 1
    let slug = UUID().uuidString.lowercased()
    let item = StoredNoteItem(
      section: section.rawValue, slug: slug, text: text, spanStart: nil, spanEnd: nil,
      edited: true, resolved: false, order: order)
    item.session = session
    modelContext.insert(item)
    if section == .openThreads {
      let thread = StoredThread(text: text, sourceNoteItemSlug: slug)
      thread.order = (session.openedThreads ?? []).count
      thread.sourceSession = session
      thread.sessionStartedAt = session.startedAt
      modelContext.insert(thread)
      try refreshOpenThreadCount(session)
    }
    try modelContext.save()
    return item.id
  }

  /// Marks a thread resolved, in the session that picked it up when there is one.
  public func resolve(thread threadID: UUID, in sessionID: UUID? = nil) throws {
    var descriptor = FetchDescriptor<StoredThread>(predicate: #Predicate { $0.id == threadID })
    descriptor.fetchLimit = 1
    guard let thread = try modelContext.fetch(descriptor).first else {
      throw StoreError.missingThread(threadID)
    }
    thread.resolved = true
    thread.resolvedAt = .now
    thread.resolvedIn = try sessionID.map { try session($0) }
    let slug = thread.sourceNoteItemSlug
    let section = NoteSection.openThreads.rawValue
    if let item = (thread.sourceSession?.items ?? []).first(where: {
      $0.slug == slug && $0.section == section
    }) {
      item.resolved = true
    }
    if let source = thread.sourceSession { try refreshOpenThreadCount(source) }
    try modelContext.save()
  }

  func item(_ id: UUID) throws -> StoredNoteItem {
    var descriptor = FetchDescriptor<StoredNoteItem>(predicate: #Predicate { $0.id == id })
    descriptor.fetchLimit = 1
    guard let item = try modelContext.fetch(descriptor).first else {
      throw StoreError.missingItem(id)
    }
    return item
  }

  func thread(for item: StoredNoteItem) -> StoredThread? {
    guard item.section == NoteSection.openThreads.rawValue else { return nil }
    return (item.session?.openedThreads ?? []).first { $0.sourceNoteItemSlug == item.slug }
  }
}
