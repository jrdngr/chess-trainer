import Book
import ChessCore

/// What Growth changes in the app's state: `useStore`'s addLine for Growth; its removes are the Playbook's.
extension AppState {
  /// Grow a line in a side's tree, Growth's moves labelled Growth or Engine.
  public mutating func addGrowthLine(_ repertoireId: String, _ line: [String], _ index: ReferenceIndex) {
    addLine(repertoireId, line, .each(growthSource(index)), via: .growth)
  }
}

/// The offer a finished run earns, read after it is logged: `SurvivalScreen.offerFor`.
/// Autopilot grows on its own fixed prefs; a Survival run you set up, on Growth's saved ones.
public func offerFor(
  _ state: AppState, _ tree: OpeningTree, _ index: ReferenceIndex, _ finish: Finish, region: String, growth: GrowthPrefs = AUTO_GROWTH
) -> GrowOffer? {
  guard let clean = finish.clean, let rep = state.repertoireList.first(where: { $0.color == finish.ended.run.color }) else { return nil }
  let entered = finish.ended.run.enteredIn.map { nodeById(tree, $0) }
  let opening = offerOpening(tree, nodeById(tree, region), entered, clean)
  return growOfferAt(
    rep: rep, index: index, tree: tree, opening: opening, played: clean, rounds: state.score.rounds,
    minShare: growth.minShare, maxPly: growth.maxPly, stub: finish.stub)
}
