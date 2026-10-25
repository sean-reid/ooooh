import Foundation

/// What the compaction model returns. Applied by the client, never trusted blindly.
public struct StatePatch: Codable, Equatable, Sendable {
  public var currentThread: String?
  public var mode: CompactState.Mode?
  public var recentTopics: [String]?
  public var add: [Addition]
  public var resolve: [String]
  public var remove: [String]

  public init(
    currentThread: String? = nil,
    mode: CompactState.Mode? = nil,
    recentTopics: [String]? = nil,
    add: [Addition] = [],
    resolve: [String] = [],
    remove: [String] = []
  ) {
    self.currentThread = currentThread
    self.mode = mode
    self.recentTopics = recentTopics
    self.add = add
    self.resolve = resolve
    self.remove = remove
  }

  public struct Addition: Codable, Equatable, Sendable {
    public var list: ListName
    public var id: String
    public var text: String

    public init(list: ListName, id: String, text: String) {
      self.list = list
      self.id = id
      self.text = text
    }
  }

  public enum ListName: String, Codable, Sendable {
    case mainIdeas, openQuestions, uncertainties, decisions
  }
}

public enum PatchError: Error, Equatable, Sendable {
  case duplicateID(String)
  case unknownID(String)
  case emptyText(String)
  case listOverflow(StatePatch.ListName, limit: Int)
}

public struct PatchLimits: Sendable {
  public var perList: Int
  public var recentTopics: Int

  public init(perList: Int = 12, recentTopics: Int = 6) {
    self.perList = perList
    self.recentTopics = recentTopics
  }

  public static let standard = PatchLimits()
}

extension CompactState {
  /// Applies a patch or throws, leaving the state untouched on failure.
  public func applying(_ patch: StatePatch, limits: PatchLimits = .standard) throws(PatchError)
    -> CompactState
  {
    var next = self
    var known = Set(allItems.map(\.id))

    for addition in patch.add {
      let text = addition.text.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !text.isEmpty else { throw .emptyText(addition.id) }
      guard known.insert(addition.id).inserted else { throw .duplicateID(addition.id) }
      let item = Item(id: addition.id, text: text)
      next[addition.list].append(item)
      if next[addition.list].count > limits.perList {
        throw .listOverflow(addition.list, limit: limits.perList)
      }
    }
    for id in patch.resolve {
      guard known.contains(id) else { throw .unknownID(id) }
      next.mutateItem(id) { $0.resolved = true }
    }
    for id in patch.remove {
      guard known.contains(id) else { throw .unknownID(id) }
      next.removeItem(id)
    }
    if let thread = patch.currentThread { next.currentThread = thread }
    if let mode = patch.mode { next.mode = mode }
    if let topics = patch.recentTopics {
      next.recentTopics = Array(topics.suffix(limits.recentTopics))
    }
    return next
  }

  public var allItems: [Item] {
    mainIdeas + openQuestions + uncertainties + decisions
  }

  subscript(list: StatePatch.ListName) -> [Item] {
    get {
      switch list {
      case .mainIdeas: mainIdeas
      case .openQuestions: openQuestions
      case .uncertainties: uncertainties
      case .decisions: decisions
      }
    }
    set {
      switch list {
      case .mainIdeas: mainIdeas = newValue
      case .openQuestions: openQuestions = newValue
      case .uncertainties: uncertainties = newValue
      case .decisions: decisions = newValue
      }
    }
  }

  private mutating func mutateItem(_ id: String, _ change: (inout Item) -> Void) {
    for list in [StatePatch.ListName.mainIdeas, .openQuestions, .uncertainties, .decisions] {
      if let index = self[list].firstIndex(where: { $0.id == id }) {
        change(&self[list][index])
      }
    }
  }

  private mutating func removeItem(_ id: String) {
    for list in [StatePatch.ListName.mainIdeas, .openQuestions, .uncertainties, .decisions] {
      self[list].removeAll { $0.id == id }
    }
  }
}
