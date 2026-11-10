import ChessCore

/// Autopilot's rounds: what the next run is, and where it starts.
/// Your logged mistakes (`evidenceIn`) steer
/// both the pick and the run.

/// What Autopilot's next run is: the recommendation, and for a run started at a position, the moves to it.
public struct AutoRound: Sendable {
  public var pick: Recommendation
  public var at: [String]?
  /// A gap's line the run steers to, when a new move is due.
  public var aim: [String]? = nil
}

/// What a session remembers of its runs so far, oldest first.
public struct AutoHistory: Sendable {
  public var focuses: [Focus] = []
  public var steered: [Bool] = []
  public init() {}
}

/// Everything the recommendation needs, read off the state.
public func recommendInput(_ state: AppState, _ tree: OpeningTree, _ selection: Selection, _ history: AutoHistory) -> RecommendInput {
  var input = RecommendInput(
    tree: tree, selection: selection, reps: repertoiresIn(state.repertoireList, selection.color), cards: state.cards,
    repairs: repairRefs(evidenceIn(state, tree, selection)), score: state.score, newPerSession: AUTO_DRILL.newPerSession,
    recentFocuses: history.focuses)
  input.recentSteered = history.steered
  input.seen = Seen(at: state.score.seen, round: state.score.lineRounds)
  return input
}

/// Your prep accuracy across the last few runs on these sides.
public func prepAccuracy(_ rounds: [RoundRecord], _ colors: [Color]) -> Double? {
  let runs = rounds.filter { $0.mode == .survival && ($0.prep?.asked ?? 0) > 0 && colors.contains($0.color) }
  let recent = runs.suffix(ACCURACY_RUNS)
  let asked = recent.reduce(0) { $0 + $1.prep!.asked }
  return asked > 0 ? Double(recent.reduce(0) { $0 + $1.prep!.found }) / Double(asked) : nil
}

/// Rounds of any mode an opening has had.
public func roundsIn(_ score: ScoreState, _ openingId: String) -> Int {
  nodeStats(score, openingId).byMode.values.reduce(0) { $0 + $1.rounds }
}

/// Autopilot's next run, or nil with nothing prepared inside the selection.
public func nextRound(_ state: AppState, _ tree: OpeningTree, _ selection: Selection, _ history: AutoHistory) -> AutoRound? {
  // A new move is due: the run heads for the gap that most wants one.
  if let gap = steerGap(state, tree, selection) {
    let region = nodeById(tree, selection.opening)
    let opening = deepestNodeWithin(tree, region, gap.path)
    return AutoRound(pick: Recommendation(focus: .test, opening: opening, color: gap.color, start: .first), at: nil, aim: gap.line)
  }
  guard var recommended = recommend(recommendInput(state, tree, selection, history)) else { return nil }
  // Freeform always starts from move one; the opponent still steers toward the pick.
  if state.settings.start == .freeform { recommended.start = .first }
  if recommended.start == .first { return AutoRound(pick: recommended, at: nil) }
  let rep = state.repertoireList.first { $0.color == recommended.color }
  let items = rep.map { itemsInRegion(tree, recommended.opening, allItems([$0])) } ?? []
  let (wayIn, inside) = splitItems(items, recommended.opening.sans.count)
  let round = state.score.lineRounds
  let deeper = insideStart(inside, state.cards, accuracy: prepAccuracy(state.score.rounds, [recommended.color]), round: round)
  let firstTime = roundsIn(state.score, recommended.opening.id) == 0
  let kind = chooseStart(
    recent: state.score.starts, cold: coldNeed(wayIn, state.cards, round), inside: deeper?.need, firstTime: firstTime)
  // With none of your moves past the opening's own position, a position start would play
  // your whole prep for you: the run starts from move one instead.
  let nothingInside = inside.isEmpty && !firstTime
  if kind == .cold || (kind == .position && nothingInside) {
    var pick = recommended
    pick.start = .first
    return AutoRound(pick: pick, at: nil)
  }
  if kind == .inside, let deeper { return AutoRound(pick: recommended, at: deeper.item.pathSans) }
  return AutoRound(pick: recommended, at: nil)
}

/// A run played: what the session remembers of it.
public func afterRound(_ history: AutoHistory, _ round: AutoRound, _ selection: Selection) -> AutoHistory {
  var next = history
  next.focuses.append(round.pick.focus)
  next.steered.append(isSteered(opening: round.pick.opening, start: round.pick.start, selection))
  return next
}

/// The Survival run Autopilot plays for a round.
public func survivalOptions(_ round: AutoRound, _ state: AppState, _ tree: OpeningTree, _ selection: Selection, seed: Double) -> StartOptions {
  var opts = StartOptions(steer: .lines, tree: tree, reps: state.repertoireList, node: nodeById(tree, selection.opening), color: round.pick.color == .w ? .w : .b)
  opts.lean = LEAN_FOR[round.pick.focus]
  opts.toward = round.pick.opening
  opts.enter = round.pick.start == .inside
  opts.at = round.at
  opts.aim = round.aim
  // The saved selection's mistakes.
  let evidence = evidenceIn(state, tree, state.settings.selection)
  opts.weakness = weaknessFromCards(state.cards, slips(evidence))
  opts.growth = GrowthOptions(minShare: AUTO_GROWTH.minShare, maxPly: AUTO_GROWTH.maxPly)
  opts.seen = Seen(at: state.score.seen, round: state.score.lineRounds)
  opts.seed = seed
  return opts
}
