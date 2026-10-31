import Book
import ChessCore

/// What Growth changes in the app's state: `useStore`'s addLine and removeLine for Growth.
extension AppState {
  /// Grow a line in a side's tree, Growth's moves labelled Growth or Engine.
  public mutating func addGrowthLine(_ repertoireId: String, _ line: [String], _ index: ReferenceIndex) {
    guard let rep = repertoires[repertoireId] else { return }
    repertoires[repertoireId] = addLine(rep, line, .each(growthSource(index))).rep
  }

  public mutating func removeLine(_ repertoireId: String, _ nodeId: String) {
    guard let rep = repertoires[repertoireId] else { return }
    repertoires[repertoireId] = pruneLine(rep, nodeId)
  }
}

/// The offer a finished run earns, read after it is logged: `SurvivalScreen.offerFor`.
public func offerFor(_ state: AppState, _ tree: OpeningTree, _ index: ReferenceIndex, _ finish: Finish, region: String) -> GrowOffer? {
  guard let clean = finish.clean, let rep = state.repertoireList.first(where: { $0.color == finish.ended.run.color }) else { return nil }
  let entered = finish.ended.run.enteredIn.map { nodeById(tree, $0) }
  let opening = offerOpening(tree, nodeById(tree, region), entered, clean)
  return growOfferAt(
    rep: rep, index: index, tree: tree, opening: opening, played: clean, rounds: state.score.rounds,
    minShare: AUTO_GROWTH.minShare, maxPly: AUTO_GROWTH.maxPly, starred: state.settings.favoriteOpenings, stub: finish.stub)
}
