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
  /// Freeform: from move one with nothing drawn; the opponent weighs its replies at each turn.
  public var free = false
  /// Freeform: the lines of gaps due a new move, which the opponent leans toward.
  public var due: [[String]] = []
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

/// Autopilot's next run, or nil with nothing prepared inside the selection.
public func nextRound(_ state: AppState, _ tree: OpeningTree, _ selection: Selection, _ history: AutoHistory) -> AutoRound? {
  if state.settings.start == .freeform { return freeRound(state, tree, selection, history) }
  let accuracy = { (color: Color) in prepAccuracy(state.score.rounds, [color]) }
  // A new move is due: the run heads for the gap that most wants one, from your move most due on its line.
  if let gap = steerGap(state, tree, selection) {
    let region = nodeById(tree, selection.opening)
    let opening = deepestNodeWithin(tree, region, gap.path)
    let line = gap.line
    let onLine = state.repertoireList.filter { $0.id == gap.repertoireId }.flatMap { allItems([$0]) }.filter { item in
      item.pathSans.count < gap.hole.path.count && Array(line.prefix(item.pathSans.count)) == item.pathSans
        && item.expected.contains { $0.san == line[item.pathSans.count] }
    }
    let start = drillStart(onLine, state.cards, accuracy: accuracy(gap.color), round: state.score.lineRounds)
    let pick = Recommendation(focus: .test, opening: opening, color: gap.color, start: .inside)
    // With no move of yours on the line to start at, past your first move as White, the run starts at the hole.
    return AutoRound(pick: pick, at: start?.item.pathSans ?? gap.hole.path, aim: line)
  }
  guard let recommended = recommend(recommendInput(state, tree, selection, history)) else { return nil }
  let rep = state.repertoireList.first { $0.color == recommended.color }
  let items = rep.map { itemsInRegion(tree, recommended.opening, allItems([$0])) } ?? []
  var pick = recommended
  pick.start = .inside
  let start = drillStart(items, state.cards, accuracy: accuracy(recommended.color), round: state.score.lineRounds)
  return AutoRound(pick: pick, at: start?.item.pathSans)
}

/// A Freeform round: the side the recommendation picks, from move one, steered only
/// toward the opening picked on Home. Gaps due a new move are leaned toward, never set as the goal.
func freeRound(_ state: AppState, _ tree: OpeningTree, _ selection: Selection, _ history: AutoHistory) -> AutoRound? {
  guard let recommended = recommend(recommendInput(state, tree, selection, history)) else { return nil }
  let pick = Recommendation(focus: recommended.focus, opening: nodeById(tree, selection.opening), color: recommended.color, start: .first)
  return AutoRound(pick: pick, at: nil, free: true, due: dueGapLines(state, tree, selection, color: recommended.color))
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
  opts.free = round.free
  opts.due = round.due
  // The saved selection's mistakes.
  let evidence = evidenceIn(state, tree, state.settings.selection)
  opts.weakness = weaknessFromCards(state.cards, slips(evidence))
  opts.growth = GrowthOptions(minShare: AUTO_GROWTH.minShare, maxPly: AUTO_GROWTH.maxPly)
  opts.seen = Seen(at: state.score.seen, round: state.score.lineRounds)
  opts.seed = seed
  return opts
}
