import ChessCore
import Foundation
import Model
import Testing

/// Golden/cases/functions/onboarding.json: whose an opening is, the selection
/// picks imply, and what finishing onboarding puts in.
@Test func onboardingCases() throws {
  let tree = openingTree(bookIndex)
  let at = 1_790_845_200_000.0

  /// A Playbook without node ids: each side's lines, where each move came from, and what the Playbook lists.
  func written(_ rep: Playbook) -> JSON {
    obj([
      "color": rep.color.rawValue, "name": rep.name,
      "lines": leafLines(rep).map { pathTo(rep, $0.tipId).map { "\($0.san)(\($0.source.rawValue))" }.joined(separator: " ") },
      "openings": familiesIn(rep, bookIndex).map(\.name),
    ])
  }

  func finish(_ openings: [SeedOpening]) -> JSON {
    var state = AppState()
    Env.at(at) { state.onboarded(tree, openings) }
    return obj([
      "playbook": state.playbookList.map(written).json,
      "selection": encoded(state.settings.selection),
      "onboarded": state.settings.onboarded,
      "events": state.events.map(eventJSON).json,
    ])
  }

  try check("onboarding", [
    "onboarding.playerOf": { playerOf(line($0[0].string)).rawValue.json },
    "onboarding.selectionFor": { a in
      encoded(selectionFor(a[0].array.map { ($0.string, playerOf(line($0.string))) }))
    },
    "onboarding.onboarded (the recommended openings)": { _ in finish(RECOMMENDED_OPENINGS) },
    "onboarding.onboarded": { a in finish(a[0].array.map { seedFor(line($0.string)) }) },
  ])
}

/// An event as the cases record it: without its time or playbook id.
func eventJSON(_ event: AppEvent) -> JSON {
  guard case .object(var o) = encoded(event) else { return .null }
  o["at"] = nil
  o["playbookId"] = nil
  return .object(o)
}
