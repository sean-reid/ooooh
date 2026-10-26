import Governor
import Session

/// The Challenge prompts switch, off. A check the governor would answer with a challenge is
/// handed on with no moment, so nothing arms; its finished and command answers stand.
struct ChallengeFilter: Sendable {
  let config: GovernorConfig

  func wrap(_ dependencies: SessionLoop.Dependencies) -> SessionLoop.Dependencies {
    var dependencies = dependencies
    dependencies.decisions = Decisions(
      base: dependencies.decisions, governor: Governor(config: config))
    return dependencies
  }

  private struct Decisions: DecisionProvider {
    let base: any DecisionProvider
    let governor: Governor

    func check(_ input: CheckInput) async throws -> JevAnswers {
      var answers = try await base.check(input)
      guard governor.kind(for: answers) == .challenge else { return answers }
      answers.goodMoment = .init(0)
      answers.cues = [:]
      return answers
    }
  }
}
