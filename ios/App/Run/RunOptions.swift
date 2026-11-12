import Book
import ChessCore
import Model

/// The run Run's own screen starts. Your setup steers it, your cards and your mistakes say where
/// it leans, and it plays inside the selection taken for this run.
func runStart(_ prefs: RunPrefs, _ selection: Selection, _ state: AppState, _ tree: OpeningTree, seed: Double) -> StartOptions {
  let evidence = evidenceIn(state, tree, state.settings.selection)
  var opts = StartOptions(steer: prefs.steer, tree: tree, reps: state.playbookList, node: nodeById(tree, selection.opening), color: selection.color)
  opts.weakness = weaknessFromCards(state.cards, slips(evidence), round: state.score.lineRounds)
  let growth = state.settings.growth
  opts.growth = GrowthOptions(minShare: growth.minShare, maxPly: growth.maxPly)
  opts.seen = Seen(at: state.score.seen, round: state.score.lineRounds)
  opts.seed = seed
  return opts
}
