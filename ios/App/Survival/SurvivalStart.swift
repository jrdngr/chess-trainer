import Book
import ChessCore
import Model

/// The run Survival's own screen starts. Your setup steers it, your cards and your mistakes say where
/// it leans, and it plays inside the selection taken for this run.
func survivalStart(_ prefs: SurvivalPrefs, _ selection: Selection, _ state: AppState, _ tree: OpeningTree, seed: Double) -> StartOptions {
  let evidence = evidenceIn(state, tree, state.settings.selection)
  var opts = StartOptions(steer: prefs.steer, tree: tree, reps: state.repertoireList, node: nodeById(tree, selection.opening), color: selection.color)
  opts.weakness = weaknessFromCards(state.cards, slips(evidence))
  let growth = state.settings.growth
  opts.growth = GrowthOptions(minShare: growth.minShare, maxPly: growth.maxPly, pastBook: growth.pastBook)
  opts.seen = Seen(at: state.score.seen, round: state.score.lineRounds)
  opts.seed = seed
  return opts
}
