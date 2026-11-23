import ChessCore
import Foundation
import Model

/// The engine as Run's judge, as two async calls. What the position is worth, and what it is worth with your
/// move forced, both from one search, plus the engine's own move.

/// How long the engine thinks about each question, at most.
public let THINK_MS: Double = 700
/// A search this deep settles a question early: a sound move needs no more.
public let QUICK_DEPTH = 14
/// How far a suspected blunder is confirmed: this deep, capped at this long.
public let CONFIRM_DEPTH = 16
public let CONFIRM_MS: Double = 4000

/// The engine's first answer for the position on the board.
public struct Baseline: Sendable, Equatable {
  public var fen: String
  /// White's side.
  public var cp: Double
  /// The engine's move, as SAN and UCI.
  public var best: String?
  public var bestUci: String?
  /// Its second choice, when it was asked for two.
  public var second: (cp: Double, uci: String)?

  public static func == (a: Baseline, b: Baseline) -> Bool {
    a.fen == b.fen && a.cp == b.cp && a.bestUci == b.bestUci && a.second?.uci == b.second?.uci && a.second?.cp == b.second?.cp
  }

  /// The position is a moment.
  public func isMomentFor(_ color: Color) -> Bool { isMoment(color, cp, second?.cp) }
}

private func colorBest(_ color: Color, _ a: Double, _ b: Double) -> Double {
  color == .w ? max(a, b) : min(a, b)
}

/// A forced mate reads as a huge swing.
private func scoreOf(_ line: EngineLine) -> Double? {
  if let cp = line.cp { return cp }
  if let mate = line.mate { return mate > 0 ? 10_000 : -10_000 }
  return nil
}

/// Weigh the position in front of you.
public func baseline(_ engine: ChessEngine, _ fen: String, moments: Bool) async -> Baseline? {
  let snap = await engine.analyse(fen, EngineLimits(depth: QUICK_DEPTH, movetime: THINK_MS, multiPv: moments ? 2 : 1))
  guard let line = snap.lines.first, let cp = scoreOf(line) else { return nil }
  let best = line.pv.first.flatMap { applyUci(fen, $0)?.san }
  let next = moments && snap.lines.count > 1 ? snap.lines[1] : nil
  let second = next.flatMap { n in n.pv.first.flatMap { uci in scoreOf(n).map { (cp: $0, uci: uci) } } }
  return Baseline(fen: fen, cp: cp, best: best, bestUci: line.pv.first, second: second)
}

/// The result with best play for `color`, where the tablebase or a known ending settles it.
public func exactResult(_ fen: String, for color: Color) -> EndResult? {
  Tablebase.probe(fen, for: color) ?? knownEnding(fen)?.result(for: color)
}

private final class Clock: @unchecked Sendable {
  let started = Date()
  var elapsed: Double { Date().timeIntervalSince(started) * 1000 }
}

/// Judge your move against the baseline: a sound move settles at the quick
/// check, a suspected blunder waits for the whole search. From a book
/// position, Stockfish's score in `BookScores` decides. `reached` is true
/// once the game has been an endgame, so its endgame rules stay on. Before
/// then, a costly move is a blunder only when the engine's line after it
/// shows why (`punishment`); otherwise it stands, with its cost.
public func judge(
  _ engine: ChessEngine, _ base: Baseline, san: String, uci: String, color: Color, moments: Bool, reached: Bool = false
) async -> Judgement {
  let endgame = reached || isEndgame(base.fen)
  let theirs = base.bestUci.flatMap { $0 != uci ? $0 : nil }
  let moment = moments && base.isMomentFor(color)
  /// At a moment you missed, the second best is what your move answers to.
  let second = moment && theirs != nil ? base.second.flatMap { $0.uci != uci ? $0.uci : nil } : nil
  let clock = Clock()
  /// Stockfish's word on your move, when the position is in the book.
  let book = BookScores.score(base.fen, uci)
  /// The exact results before and after your move, where the tablebase or a known ending settles both positions.
  let exact: (before: EndResult, after: EndResult)? = {
    guard let before = exactResult(base.fen, for: color),
      let next = applyUci(base.fen, uci), let after = exactResult(next.after, for: color)
    else { return nil }
    return (before, after)
  }()

  @Sendable func weigh(_ snap: EngineSnapshot) -> (
    ok: Bool, lost: Double, before: Double, after: Double, found: Bool, reply: String?, missedMate: Bool, yours: EngineLine, top: EngineLine,
    ref: EngineLine
  )? {
    guard let yours = snap.lines.first(where: { $0.pv.first == uci }) else { return nil }
    let top = theirs.flatMap { t in snap.lines.first { $0.pv.first == t } } ?? (theirs == nil ? yours : nil)
    guard let top else { return nil }
    if snap.thinking && yours.depth != top.depth { return nil }
    let next = second.flatMap { s in snap.lines.first { $0.pv.first == s } }
    if second != nil && (next == nil || (snap.thinking && next!.depth != yours.depth)) { return nil }
    guard let yourCp = scoreOf(yours), let topCp = scoreOf(top) else { return nil }
    // Your move scored above the engine's: nothing lost.
    let before = colorBest(color, topCp, yourCp)
    let result = judgeMove(base.fen, color, before, yourCp, exact: exact, reached: endgame)
    let found = moment && result.lost <= MOMENT_FOUND
    // A moment missed is judged against the next best move.
    let nextCp = next.flatMap(scoreOf)
    // Your move is the next best itself: the chance is missed, and nothing else is lost.
    let playedNext = moment && !found && base.second?.uci == uci
    let ok = playedNext || (moment && !found && nextCp != nil ? judgeMove(base.fen, color, colorBest(color, nextCp!, yourCp), yourCp, exact: exact, reached: endgame).ok : result.ok)
    // In an endgame, a mate the engine had and your move doesn't keep: the run goes on, but you hear about it.
    func mates(_ line: EngineLine) -> Bool { line.mate.map { ($0 > 0) == (color == .w) } ?? false }
    let missedMate = endgame && mates(top) && !mates(yours)
    // The line your move answers to: at a moment missed, the next best's, as for its cost.
    let ref = moment && !found ? next ?? top : top
    return (ok, result.lost, before, yourCp, found, yours.pv.count > 1 ? yours.pv[1] : nil, missedMate, yours, top, ref)
  }

  /// The engine's line after your move, where it shows why your move is a blunder: see `punishment`.
  @Sendable func reason(_ yours: EngineLine, _ top: EngineLine) -> PunishLine? {
    let mated = yours.mate.flatMap { ($0 > 0) == (color == .w) ? nil : Int(abs($0)) }
    return punishment(base.fen, color, yours: yours.pv, best: top.pv, mated: mated)
  }
  /// A costly move counts as a blunder: in an endgame by its result, before it only with a reason.
  @Sendable func fails(_ verdict: (ok: Bool, yours: EngineLine, ref: EngineLine)) -> Bool {
    !verdict.ok && (endgame || exact != nil || reason(verdict.yours, verdict.ref) != nil)
  }

  let searchmoves = second != nil ? [theirs!, second!, uci] : theirs != nil ? [theirs!, uci] : [uci]
  let snap = await engine.analyse(
    base.fen,
    EngineLimits(depth: CONFIRM_DEPTH, movetime: CONFIRM_MS, multiPv: searchmoves.count, searchmoves: searchmoves)
  ) { snap in
    // A sound move, a costly one the engine's line shows no reason for, or one the tablebase or a known ending
    // already settles, is settled at the quick check.
    guard let verdict = weigh(snap) else { return false }
    return (!fails((verdict.ok, verdict.yours, verdict.ref)) || theirs == nil || exact != nil || book != nil) && (clock.elapsed >= THINK_MS || snap.depth >= QUICK_DEPTH)
  }
  var verdict = weigh(snap)
  // A search cut short can leave out your move's line, or end it after your move, so it can't show why a costly move
  // is a blunder. Before the endgame, such a move is searched once more to its full depth for its line.
  let sign: Double = color == .w ? 1 : -1
  let bookCostly = book.map { !judgeMove(base.fen, color, sign * Double($0.best), sign * Double($0.best - $0.lost)).ok } ?? false
  let costly = bookCostly || verdict.map { !$0.ok } ?? false
  if costly && theirs != nil && !endgame && exact == nil && (verdict?.yours.pv.count ?? 0) < 2 {
    let full = await engine.analyse(
      base.fen, EngineLimits(depth: CONFIRM_DEPTH, movetime: CONFIRM_MS, multiPv: searchmoves.count, searchmoves: searchmoves))
    if let again = weigh(full) { verdict = again }
  }
  var judged = Judgement(
    san: san, ok: verdict?.ok ?? exact.map { $0.after >= $0.before } ?? true, lost: verdict?.lost ?? 0, best: base.best, before: verdict?.before ?? base.cp,
    after: verdict?.after ?? base.cp, moment: moment, found: verdict?.found ?? false, reply: verdict?.reply ?? nil,
    missedMate: verdict?.missedMate ?? false, exact: exact.map { ResultSlip(from: $0.before, to: $0.after) })
  if let verdict {
    judged.yours = verdict.yours.pv
    judged.top = verdict.top.pv
    judged.depth = verdict.yours.depth
  }
  // Your move is the engine's own choice: sound, and at a moment, found.
  if theirs == nil {
    judged.ok = true
    judged.lost = 0
    judged.found = moment
    judged.missedMate = false
  }
  // From a book position, Stockfish's verdict stands, except at a moment, which the engine judges against its second best.
  if let book, exact == nil, !moment {
    let before = sign * Double(book.best), after = sign * Double(book.best - book.lost)
    let verdict = judgeMove(base.fen, color, before, after)
    judged.ok = verdict.ok
    judged.lost = verdict.lost
    judged.before = before
    judged.after = after
  }
  // Before the endgame, a blunder needs a reason the engine's line can show: material lost soon, or a mate.
  // With no line from the engine there is no reason to show, so the move stands.
  if !judged.ok && !endgame && exact == nil {
    if let verdict, let line = reason(verdict.yours, verdict.ref) {
      judged.line = line.moves
      judged.lineBefore = line.before
    } else {
      judged.ok = true
    }
  }
  return judged
}
