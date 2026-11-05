import ChessCore

/// What became of a plan's steps over the game: done, gone, or still open,
/// and the plans the game has left behind.

public enum StepMark: String, Equatable, Sendable {
  /// You did it.
  case done
  /// It can no longer be done.
  case gone
}

/// A plan on the card, with each step's mark; nil is still open.
public struct ShownPlan: Equatable, Sendable {
  public var plan: Plan
  public var marks: [StepMark?]
  public init(plan: Plan) {
    self.plan = plan
    marks = Array(repeating: nil, count: plan.steps.count)
  }
}

/// The plan now, and the ones before it, newest first.
public struct PlanTrail: Equatable, Sendable {
  public var current: ShownPlan?
  public var earlier: [ShownPlan] = []
  public init() {}
}

/// How a step stands on this board, from your side. Steps are placed for the board;
/// their needs are read with side `a`.
public func markOf(_ step: PlanStep, _ fen: String, _ facts: PlanFacts, me: Color, a: Color) -> StepMark? {
  let them = me.other
  if let goals = step.goals, goals.contains(where: { goalRoute(fen, me, $0).done }) { return .done }
  switch step.check {
  case .castle(let long)?:
    let king = facts.king(me)
    if king == (long ? .long : .short) { return .done }
    if king == (long ? .short : .long) || (king == .center && !facts.canCastle(me, long: long)) { return .gone }
  case .trade(let light)?:
    if !facts.bishop(them, light: light) { return .done }
    if !facts.bishop(me, light: light) { return .gone }
  case .file(let file)?:
    if facts.rook(me, file: fileIndex(file)) { return .done }
    if !facts.fileFree(me, fileIndex(file)) { return .gone }
  case .keepBishop(let light)?:
    if !facts.bishop(me, light: light) { return .gone }
  case nil:
    break
  }
  if let goals = step.goals, !goals.isEmpty, goals.allSatisfy({ goalGone($0, facts, me) }) { return .gone }
  if !step.needs.allSatisfy({ holds($0, facts, a: a) }) { return .gone }
  return nil
}

/// A goal no piece of yours can reach: no pawn behind the square on its file, or none of the piece left.
func goalGone(_ goal: Goal, _ facts: PlanFacts, _ me: Color) -> Bool {
  let target = coords(goal.to)
  if goal.piece == .p {
    return !facts.pawns(me, file: target.file).contains { rel(me, coords($0.square).rank) < rel(me, target.rank) }
  }
  return facts.count(me, goal.piece) == 0
}

/// Marks what this board settles. A tick stays; a cross can still turn into a tick.
func remark(_ shown: inout ShownPlan, _ fen: String, _ facts: PlanFacts, _ me: Color) {
  for (i, step) in shown.plan.steps.enumerated() where shown.marks[i] != .done {
    if let mark = markOf(step, fen, facts, me: me, a: shown.plan.a) { shown.marks[i] = mark }
  }
}

/// The trail one move on: the current plan's marks first, then the plan for the new board.
/// A plan that leaves goes to the front of the earlier ones; one that comes back keeps its marks.
public func advanceTrail(_ trail: PlanTrail, _ fen: String, _ me: Color) -> PlanTrail {
  var out = trail
  let facts = PlanFacts(fen)
  if var current = out.current {
    remark(&current, fen, facts, me)
    out.current = current
  }
  let next = planOf(fen, me, kept: out.current?.plan.key)
  if next?.key == out.current?.plan.key { return out }
  if let current = out.current {
    out.earlier.removeAll { $0.plan.key == current.plan.key }
    out.earlier.insert(current, at: 0)
  }
  guard let next else {
    out.current = nil
    return out
  }
  var shown = out.earlier.firstIndex { $0.plan.key == next.key }.map { out.earlier.remove(at: $0) } ?? ShownPlan(plan: next)
  remark(&shown, fen, facts, me)
  out.current = shown
  return out
}

/// The trail over a game's positions, first to last.
public func planTrail(_ fens: [String], _ me: Color) -> PlanTrail {
  fens.reduce(PlanTrail()) { advanceTrail($0, $1, me) }
}

/// How many steps of a plan were done and how many went.
public func markTally(_ shown: ShownPlan) -> (done: Int, gone: Int) {
  (shown.marks.filter { $0 == .done }.count, shown.marks.filter { $0 == .gone }.count)
}

/// The first move toward an open step, as UCI, where it is legal now: a castle,
/// a pawn's next square, or the first hop of a piece's route. Nil for steps no
/// single move starts.
public func firstMove(_ step: PlanStep, _ fen: String, _ me: Color) -> String? {
  guard fenTurn(fen) == me else { return nil }
  if case .castle(let long)? = step.check {
    return applySan(fen, long ? "O-O-O" : "O-O")?.uci
  }
  for goal in step.goals ?? [] {
    guard let first = goalRoute(fen, me, goal).arrows.first else { continue }
    var to = first.to
    if goal.piece == .p {
      // One square, or both from home when the goal is two ahead.
      let (file, rank) = coords(first.from)
      if !(rel(me, rank) == 1 && rel(me, coords(first.to).rank) == 3) { to = sq(file, rank + forward(me)) }
    }
    if let move = applyMove(fen, from: first.from, to: to, promotion: goal.piece == .p && rel(me, coords(to).rank) == 7 ? .q : nil) {
      return move.uci
    }
  }
  return nil
}
