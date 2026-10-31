import ChessCore
import Foundation
import Model

/// The engine as Survival's judge: `src/screens/survival/useJudge.ts` as two
/// async calls. What the position is worth, and what it is worth with your
/// move forced, both from one search, plus the engine's own move.

/// How long the engine thinks about each question.
public let THINK_MS: Double = 700
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
  let snap = await engine.analyse(fen, EngineLimits(movetime: THINK_MS, multiPv: moments ? 2 : 1))
  guard let line = snap.lines.first, let cp = scoreOf(line) else { return nil }
  let best = line.pv.first.flatMap { applyUci(fen, $0)?.san }
  let next = moments && snap.lines.count > 1 ? snap.lines[1] : nil
  let second = next.flatMap { n in n.pv.first.flatMap { uci in scoreOf(n).map { (cp: $0, uci: uci) } } }
  return Baseline(fen: fen, cp: cp, best: best, bestUci: line.pv.first, second: second)
}

private final class Clock: @unchecked Sendable {
  let started = Date()
  var elapsed: Double { Date().timeIntervalSince(started) * 1000 }
}

/// Judge your move against the baseline: a sound move settles at the quick
/// check, a suspected blunder waits for the whole search.
public func judge(_ engine: ChessEngine, _ base: Baseline, san: String, uci: String, color: Color, moments: Bool) async -> Judgement {
  let theirs = base.bestUci.flatMap { $0 != uci ? $0 : nil }
  let moment = moments && base.isMomentFor(color)
  /// At a moment you missed, the second best is what your move answers to.
  let second = moment && theirs != nil ? base.second.flatMap { $0.uci != uci ? $0.uci : nil } : nil
  let clock = Clock()

  @Sendable func weigh(_ snap: EngineSnapshot) -> (ok: Bool, lost: Double, before: Double, after: Double, found: Bool, reply: String?)? {
    guard let yours = snap.lines.first(where: { $0.pv.first == uci }) else { return nil }
    let top = theirs.flatMap { t in snap.lines.first { $0.pv.first == t } } ?? (theirs == nil ? yours : nil)
    guard let top else { return nil }
    if snap.thinking && yours.depth != top.depth { return nil }
    let next = second.flatMap { s in snap.lines.first { $0.pv.first == s } }
    if second != nil && (next == nil || (snap.thinking && next!.depth != yours.depth)) { return nil }
    guard let yourCp = scoreOf(yours), let topCp = scoreOf(top) else { return nil }
    // Your move scored above the engine's: nothing lost.
    let before = colorBest(color, topCp, yourCp)
    let result = judgeByEval(color, before, yourCp)
    let found = moment && result.lost <= MOMENT_FOUND
    // A moment missed is judged against the next best move.
    let nextCp = next.flatMap(scoreOf)
    let ok = moment && !found && nextCp != nil ? judgeByEval(color, colorBest(color, nextCp!, yourCp), yourCp).ok : result.ok
    return (ok, result.lost, before, yourCp, found, yours.pv.count > 1 ? yours.pv[1] : nil)
  }

  let searchmoves = second != nil ? [theirs!, second!, uci] : theirs != nil ? [theirs!, uci] : [uci]
  let snap = await engine.analyse(
    base.fen,
    EngineLimits(depth: CONFIRM_DEPTH, movetime: CONFIRM_MS, multiPv: searchmoves.count, searchmoves: searchmoves)
  ) { snap in
    // A sound move is settled at the quick check.
    guard let verdict = weigh(snap) else { return false }
    return (verdict.ok || theirs == nil) && clock.elapsed >= THINK_MS
  }
  let verdict = weigh(snap)
  var judged = Judgement(
    san: san, ok: verdict?.ok ?? true, lost: verdict?.lost ?? 0, best: base.best, before: verdict?.before ?? base.cp,
    after: verdict?.after ?? base.cp, moment: moment, found: verdict?.found ?? false, reply: verdict?.reply ?? nil)
  // Your move is the engine's own choice: sound, and at a moment, found.
  if theirs == nil {
    judged.ok = true
    judged.lost = 0
    judged.found = moment
  }
  return judged
}
