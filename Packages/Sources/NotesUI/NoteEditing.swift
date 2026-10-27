import Notes

/// What the screen does with each edit. A view without one is read-only.
public struct NoteEditing {
  public var edit: @MainActor (NoteSection, NoteItem, String) -> Void
  public var delete: @MainActor (NoteSection, NoteItem) -> Void
  public var add: @MainActor (NoteSection, String) -> Void
  public var resolve: @MainActor (NoteItem, Bool) -> Void

  public init(
    edit: @escaping @MainActor (NoteSection, NoteItem, String) -> Void,
    delete: @escaping @MainActor (NoteSection, NoteItem) -> Void,
    add: @escaping @MainActor (NoteSection, String) -> Void,
    resolve: @escaping @MainActor (NoteItem, Bool) -> Void
  ) {
    self.edit = edit
    self.delete = delete
    self.add = add
    self.resolve = resolve
  }
}

/// A field the user is typing in: an item's text, or the add row of a section.
enum NoteDraft: Hashable {
  case item(NoteSection, String)
  case add(NoteSection)
}
