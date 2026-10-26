/// Where the free count comes from. The app fills it from the Worker's answer when a session starts.
public protocol FreeSessionCount: Sendable {
  /// Nil until the Worker has answered this launch.
  var remainingFreeSessions: Int? { get async }
}
