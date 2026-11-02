import Book
import ChessCore
import Foundation
import Shared

/// Middlegame mode: one of your Playbook lines, played on for you to a
/// middlegame, then handed to you under Survival's rules.
///
/// The handoff is built here: your line as it stands, then book moves for both
/// sides, then the engine at your level where the book runs out. Every move
/// past your line has to keep the eval near where your line ended, so the
/// position you get is the one your line earned.

/// From this ply on (after move 15) the game counts as a middlegame however it stands.
public let MIDDLEGAME_BY_PLY = 30
/// How far, in centipawns, a move played for you may take the eval from where your line ended.
public let HANDOFF_BAND: Double = 100
/// The handoff stops here at the latest, whatever the book still knows.
public let HANDOFF_MAX_PLY = 60
/// How deep the engine looks when it checks a move against the band.
public let HANDOFF_DEPTH = 6

/// Each side's knights and bishops on their own starting squares.
private let HOME_MINORS: [Color: [(square: String, type: PieceType)]] = [
  .w: [("b1", .n), ("g1", .n), ("c1", .b), ("f1", .b)],
  .b: [("b8", .n), ("g8", .n), ("c8", .b), ("f8", .b)],
]

/// How many of a side's knights and bishops are still on their own starting squares.
public func minorsAtHome(_ fen: String, _ color: Color) -> Int {
  let pieces = piecesFromFen(fen)
  return HOME_MINORS[color]!.filter { home in
    pieces.contains { $0.color == color && $0.square == home.square && $0.type == home.type }
  }.count
}

/// A side's king has castled or moved: it is off its starting square, or the side can no longer castle.
public func kingHasMoved(_ fen: String, _ color: Color) -> Bool {
  let start = color == .w ? "e1" : "e8"
  let home = piecesFromFen(fen).contains { $0.color == color && $0.type == .k && $0.square == start }
  if !home { return true }
  let fields = fen.split(separator: " ")
  let rights = fields.count > 2 ? String(fields[2]) : "-"
  return !rights.contains(color == .w ? "K" : "k") && !rights.contains(color == .w ? "Q" : "q")
}

/// A side has done the opening's jobs: at most one minor piece left at home, and the king castled or moved.
public func developed(_ fen: String, _ color: Color) -> Bool {
  minorsAtHome(fen, color) <= 1 && kingHasMoved(fen, color)
}

/// The middlegame has started: both sides are developed, or the game has reached move 15.
/// It lasts until the endgame (`isEndgame`) takes over.
public func middlegameStarted(_ fen: String, ply: Int) -> Bool {
  ply >= MIDDLEGAME_BY_PLY || (developed(fen, .w) && developed(fen, .b))
}

/// Whether a score, White's, is within the band around where your line ended.
public func inBand(_ center: Double, _ cp: Double) -> Bool {
  abs(cp - center) <= HANDOFF_BAND
}

/// A move that could be played for you: how likely it is, and the engine's score after it, White's.
public struct HandoffCandidate: Equatable, Sendable {
  public var san: String
  public var weight: Double
  public var cp: Double
  public init(san: String, weight: Double, cp: Double) {
    self.san = san
    self.weight = weight
    self.cp = cp
  }
}

/// Pick a move by its weight among those inside the band. With none inside, the one closest to it.
public func pickInBand(_ candidates: [HandoffCandidate], center: Double, _ rand: () -> Double) -> String? {
  guard !candidates.isEmpty else { return nil }
  let inside = candidates.filter { inBand(center, $0.cp) }
  if inside.isEmpty {
    return candidates.min { abs($0.cp - center) < abs($1.cp - center) }!.san
  }
  return pickWeighted(inside, { $0.weight }, rand).san
}

/// The book's moves here with how often they are played: the common ones, where there are any.
public func bookCandidates(_ index: ReferenceIndex, _ fen: String) -> [(san: String, games: Double)] {
  let moves = lookup(index, fen)?.moves ?? []
  let all = moves.reduce(0) { $0 + max(0, $1.games) }
  if moves.isEmpty || all <= 0 { return [] }
  let common = moves.filter { $0.games / all >= BOOK_SHARE }
  return (common.isEmpty ? moves : common).map { ($0.san, max(0, $0.games)) }
}

/// The engine's candidate moves at a level, weighted the way `chooseMove` picks among them.
public func levelCandidates(_ fen: String, _ lines: [EngineLine], _ level: Level) -> [HandoffCandidate] {
  let usable = lines.filter { !$0.pv.isEmpty }.jsSorted { Double($0.multipv - $1.multipv) }
  let scored = usable.compactMap { line -> (san: String, cp: Double)? in
    guard let san = applyUci(fen, line.pv[0])?.san else { return nil }
    if let cp = line.cp { return (san, cp) }
    if let mate = line.mate { return (san, mate > 0 ? 10_000 - mate : -10_000 - mate) }
    return nil
  }
  guard let best = scored.first?.cp else { return [] }
  return scored.map { move in
    let weight = level.temperature > 0 ? exp(-abs(best - move.cp) / level.temperature) : (move.cp == best ? 1 : 0)
    return HandoffCandidate(san: move.san, weight: weight, cp: move.cp)
  }
}

/// Who chose a move on the way to the handoff.
public enum HandoffKind: String, Sendable, Codable {
  /// Your Playbook's.
  case prep
  case book
  /// The engine at your level, where the book had nothing.
  case engine
}

/// The moves played for you, and where your line ended.
public struct Handoff: Equatable, Sendable {
  public var line: [String]
  /// One per ply of `line`.
  public var kinds: [HandoffKind]
  /// The engine's score where your line ended, White's: the band's center.
  public var center: Double
  /// How many plies of `line` are your own line.
  public var prep: Int { kinds.prefix { $0 == .prep }.count }
  public init(line: [String], kinds: [HandoffKind], center: Double) {
    self.line = line
    self.kinds = kinds
    self.center = center
  }
}

/// What building a handoff asks of the engine and the book.
public struct HandoffTools: Sendable {
  /// The book's moves at a position, with how often each is played.
  public var book: @Sendable (_ fen: String) -> [(san: String, games: Double)]
  /// The engine's score of a position, White's.
  public var evaluate: @Sendable (_ fen: String) async -> Double?
  /// The engine's score after each of these moves, White's, by move.
  public var score: @Sendable (_ fen: String, _ sans: [String]) async -> [String: Double]
  /// The engine's own moves at your level, weighted as it would pick them.
  public var engineMoves: @Sendable (_ fen: String) async -> [HandoffCandidate]
  public init(
    book: @escaping @Sendable (String) -> [(san: String, games: Double)],
    evaluate: @escaping @Sendable (String) async -> Double?,
    score: @escaping @Sendable (String, [String]) async -> [String: Double],
    engineMoves: @escaping @Sendable (String) async -> [HandoffCandidate]
  ) {
    self.book = book
    self.evaluate = evaluate
    self.score = score
    self.engineMoves = engineMoves
  }
}

/// Play your line out to the handoff: your moves as they are, then the book for both
/// sides, then the engine where the book runs out first, every move held to the band.
/// It stops on your turn, once the middlegame has started and the book has nothing more,
/// or once the game reaches an endgame. Nil when your line can't be played or the game ends on the way.
public func buildHandoff(_ yours: [String], color: Color, tools: HandoffTools, seed: Double) async -> Handoff? {
  let rand = mulberry32(seed: seed)
  let walk = walkSan(yours)
  guard !yours.isEmpty, walk.moves.count == yours.count, let tip = walk.fens.last,
    let center = await tools.evaluate(tip)
  else { return nil }
  var line = yours
  var kinds = [HandoffKind](repeating: .prep, count: yours.count)
  var fen = tip
  while true {
    if positionStatus(fen).gameOver { return nil }
    let ply = line.count
    let options = tools.book(fen)
    let mine = fenTurn(fen) == color
    if mine && (ply >= HANDOFF_MAX_PLY || isEndgame(fen) || (middlegameStarted(fen, ply: ply) && options.isEmpty)) { break }
    // The book's moves first, then the engine's; with none of either in the band, the closest of all.
    var book: [HandoffCandidate] = []
    if !options.isEmpty && ply < HANDOFF_MAX_PLY {
      let scores = await tools.score(fen, options.map(\.san))
      book = options.compactMap { o in scores[o.san].map { HandoffCandidate(san: o.san, weight: o.games, cp: $0) } }
    }
    var san: String?
    var kind = HandoffKind.book
    if book.contains(where: { inBand(center, $0.cp) }) {
      san = pickInBand(book, center: center, rand)
    } else {
      let engine = await engineCandidates(fen, tools)
      if engine.contains(where: { inBand(center, $0.cp) }) || book.isEmpty {
        kind = .engine
        san = pickInBand(engine, center: center, rand)
      } else {
        let closest = pickInBand(book + engine, center: center, rand)
        if !book.contains(where: { $0.san == closest }) { kind = .engine }
        san = closest
      }
    }
    guard let san, let move = applySan(fen, san) else { return nil }
    line.append(san)
    kinds.append(kind)
    fen = move.after
  }
  return Handoff(line: line, kinds: kinds, center: center)
}

/// The engine's moves at your level, each scored again as deep as the band's center,
/// so the band compares like with like.
private func engineCandidates(_ fen: String, _ tools: HandoffTools) async -> [HandoffCandidate] {
  let moves = await tools.engineMoves(fen)
  if moves.isEmpty { return [] }
  let scores = await tools.score(fen, moves.map(\.san))
  return moves.map { move in
    var out = move
    if let cp = scores[move.san] { out.cp = cp }
    return out
  }
}

/* ── the run ── */

/// What a Middlegame run's opponent steers toward: one of your lines, or one ending where your prep has a gap.
public let MIDDLEGAME_STEERS: [SurvivalSteer] = [.lines, .gaps]

/// Middlegame mode's setup. It is scored in points, so moments, missions and the combo are always on.
public let DEFAULT_MIDDLEGAME = SurvivalPrefs(
  steer: .lines, clock: .off, moveScores: true, moments: true, missions: true, combo: true,
  undefendedFlash: false)

/// A setup as the mode plays it: a steer it knows, and the extras on.
public func middlegamePrefs(_ prefs: SurvivalPrefs) -> SurvivalPrefs {
  var out = prefs
  if !MIDDLEGAME_STEERS.contains(out.steer) { out.steer = .lines }
  out.moments = true
  out.missions = true
  out.combo = true
  return out
}

/// The line a Middlegame run plays out: the one Survival's draw picked, to its end.
/// Empty when the draw found no line of yours and fell back on the opening's own moves.
/// A gap's line is yours up to the reply your Playbook has no answer for.
public func middlegameLine(_ begun: SurvivalStart, _ reps: [Repertoire]) -> [String] {
  let run = begun.state.run
  guard let rep = reps.first(where: { $0.id == run.repertoireId }), !run.target.isEmpty,
    nodeAtLine(rep, run.target) != nil || nodeAtLine(rep, Array(run.target.dropLast())) != nil
  else { return [] }
  return run.target
}

/// A run begun at the handoff. Your prep is never asked (a transposition back into
/// your Playbook grades nothing), the book phase is over before it starts, and the
/// opponent plays from the book and the engine, not from your lines.
public func beginMiddlegame(_ begun: SurvivalStart) -> RunSession {
  var session = beginSession(begun)
  session.source.prepAt = { _ in [] }
  session.source.weightsAt = { _, _ in [] }
  session.redraw = { $0 }
  session.prepStatus = .complete
  session.bookOver = true
  session.prepEnd = begun.state.run.played
  session.middlegame = true
  return session
}
