import ChessCore

/// Drill lines as a pure controller: `src/model/lineDrillController.ts`.
/// The screen owns the clock, the timers, drawing lines and the store.
/// The prototype's module functions are statics on `LineDrillController`.

/// Playing the line; a right move shown for a beat; a miss explained; or the line done and graded.
public enum LinePhase: String, Sendable { case play, flash, wrong, done }

/// The line's grade, once given, and its card as it was before.
public struct LineGraded: Equatable, Sendable {
  public var before: LineCard
  public var grade: Grade
}

public struct LineDrillState: Equatable, Sendable {
  /// The lines drawn for this group, and which one is being played.
  public var batch: [DrillLine]
  public var at = 0
  /// Which group of similar lines this is.
  public var group = 1
  public var line: DrillLine?
  /// How far into the line the board stands.
  public var ply = 0
  public var phase = LinePhase.play
  public var played: LegalMove?
  public var misses = 0
  /// Seconds each correct move of yours took, this line.
  public var times: [Double] = []
  public var graded: LineGraded?
  /// Lines finished this sitting.
  public var finished = 0
}

public enum LineEffect: Equatable, Sendable {
  case record(line: [String], correct: Bool)
  case buzz([Int])
  /// A mistake logged at this position has been put right.
  case clearMistake(String)
  case mistake(Mistake)
  /// Show the right move for a beat, then `carryOn`.
  case flash
  case round(RoundRecord)
  /// Grade the line's card; `before`, when given, is what to put it back to first. The screen answers with `graded`.
  case gradeLine(repertoireId: String, tipId: String, grade: Grade, before: LineCard?)
}

public typealias LineStep = (state: LineDrillState, effects: [LineEffect])

public enum LineDrillController {
  public static func begin(_ batch: [DrillLine]) -> LineDrillState {
    LineDrillState(batch: batch, line: batch.first)
  }

  /// Whether the board is waiting on one of your moves.
  public static func yourMove(_ s: LineDrillState, _ color: Color) -> Bool {
    guard let line = s.line else { return false }
    return s.ply < line.sans.count && yoursAt(color, s.ply)
  }

  /// The move your prep has here, when it is your move.
  public static func expectedHere(_ s: LineDrillState, _ color: Color) -> String? {
    yourMove(s, color) ? s.line!.sans[s.ply] : nil
  }

  /// The opponent's moves play themselves.
  public static func theirMove(_ s: LineDrillState, _ color: Color) -> LineDrillState {
    guard let line = s.line, s.phase == .play, !yourMove(s, color), s.ply < line.sans.count else { return s }
    var next = s
    next.ply += 1
    return next
  }

  /// You played `move`, `took` seconds after it was your turn. Another move
  /// your prep has is right too, and the line follows it.
  public static func answer(
    _ s: LineDrillState, _ color: Color, _ move: LegalMove, _ took: Double, _ rep: Repertoire, _ item: TrainingItem?, _ mistakeIds: [String]
  ) -> LineStep {
    guard let line = s.line, s.phase == .play, yourMove(s, color) else { return (s, []) }
    let expected = line.sans[s.ply]
    let right = item.map { checkAnswer($0, move.san).correct } ?? (move.san == expected)
    let asked = Array(line.sans.prefix(s.ply))
    var effects: [LineEffect] = [.record(line: right ? asked + [move.san] : asked, correct: right)]
    var next = s
    next.played = move
    if right {
      effects.append(.buzz([12]))
      if let item, mistakeIds.contains("\(item.repertoireId)#\(item.key)") {
        effects.append(.clearMistake("\(item.repertoireId)#\(item.key)"))
      }
      let along = move.san != expected ? continueLine(rep, asked + [move.san]) : nil
      effects.append(.flash)
      next.times.append(took)
      next.line = along ?? line
      next.phase = .flash
      return (next, effects)
    }
    effects.append(.buzz([18, 50, 18]))
    if let item {
      effects.append(.mistake(Mistake(
        source: .drill, repertoireId: item.repertoireId, key: item.key, fen: item.fen, path: asked, played: move.san, expected: expected)))
    }
    next.misses += 1
    next.phase = .wrong
    return (next, effects)
  }

  /// After the beat on a right move, or Continue after a miss: the line goes on.
  public static func carryOn(_ s: LineDrillState) -> LineDrillState {
    guard s.phase == .flash || s.phase == .wrong else { return s }
    var next = s
    next.played = nil
    next.ply += 1
    next.phase = .play
    return next
  }

  /// The end of the line: counted once as a round, and graded from the clock.
  public static func lineDone(_ s: LineDrillState, _ color: Color, _ tree: OpeningTree, _ region: OpeningNode, at: Double = Env.now()) -> LineStep {
    guard let line = s.line, s.phase == .play, s.ply >= line.sans.count else { return (s, []) }
    let asked = s.times.count + s.misses
    var effects: [LineEffect] = [
      .round(RoundRecord(
        mode: .drill, openingId: deepestNodeWithin(tree, region, line.sans).id, color: color, answered: asked,
        correct: s.times.count, perfect: s.misses == 0 && asked > 0, at: at, line: line.sans)),
    ]
    if asked > 0 {
      effects.append(.gradeLine(repertoireId: line.repertoireId, tipId: line.tipId, grade: gradeForLine(s.times, s.misses), before: nil))
    }
    var next = s
    next.finished += 1
    next.phase = .done
    return (next, effects)
  }

  /// The store graded the line: keep its card as it was, so the grade can be changed.
  public static func graded(_ s: LineDrillState, _ before: LineCard, _ grade: Grade) -> LineDrillState {
    var next = s
    next.graded = LineGraded(before: before, grade: grade)
    return next
  }

  /// Change the line's grade: its card goes back to before and takes the new one.
  public static func regrade(_ s: LineDrillState, _ value: Grade) -> LineStep {
    guard let line = s.line, let was = s.graded, was.grade != value else { return (s, []) }
    var next = s
    next.graded?.grade = value
    return (next, [.gradeLine(repertoireId: line.repertoireId, tipId: line.tipId, grade: value, before: was.before)])
  }

  /// Whether the next line needs a fresh draw: this group is played out.
  public static func needsDraw(_ s: LineDrillState) -> Bool {
    s.at + 1 >= s.batch.count
  }

  /// On to the next line: the next of this group, or the first of `fresh`, a new group.
  public static func nextLine(_ s: LineDrillState, _ fresh: [DrillLine]? = nil) -> LineDrillState {
    let drawn = needsDraw(s)
    let lines = drawn ? (fresh ?? []) : s.batch
    let at = drawn ? 0 : s.at + 1
    var next = LineDrillState(batch: lines, at: at, group: drawn ? s.group + 1 : s.group, line: at < lines.count ? lines[at] : nil)
    next.finished = s.finished
    return next
  }
}
