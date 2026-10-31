import Book
import ChessCore
import Shared

/// Survival: how far you get before your first blunder. Every Autopilot
/// round is one. `src/model/survival.ts`; missions are in `Missions.swift`.

/// How a move's score reads: green for eval gained, yellow or red for eval lost.
public enum ScoreTone: String, Sendable, Codable {
  case up, slight, bad
}

/// How much you can give back and still read yellow rather than red.
public let SCORE_SLIGHT: Double = 40

/// The popup for one of your moves, from the eval swing it closed on. Nil for a zero.
public func moveScore(_ swing: Double) -> (cp: Double, tone: ScoreTone)? {
  let cp = JS.round(swing)
  if cp == 0 { return nil }
  if cp > 0 { return (cp, .up) }
  return (cp, -cp <= SCORE_SLIGHT ? .slight : .bad)
}

/// The swing between two engine scores in White's frame, from your side; nil across a mate.
public func evalSwing(_ color: Color, _ from: Double, _ to: Double) -> Double? {
  if abs(from) >= 10_000 || abs(to) >= 10_000 { return nil }
  return color == .w ? to - from : from - to
}

/// The book moves at a position, most played first.
public func bookMoves(_ index: ReferenceIndex, _ fen: String) -> [String] {
  let entry = lookup(index, fen)
  let total = totalGamesAt(entry)
  guard let entry, total > 0 else { return [] }
  return entry.moves.filter { $0.games / total >= BOOK_SHARE }.jsSorted { cmp($1.games, $0.games) }.map(\.san)
}

/// Whether the book has anything at all here.
public func inTheBook(_ index: ReferenceIndex, _ fen: String) -> Bool {
  totalGamesAt(lookup(index, fen)) > 0
}

/// Whether a move the engine passed, costing `lost`, is a book move here.
public func isBookMove(_ index: ReferenceIndex, _ fen: String, _ san: String, _ lost: Double) -> Bool {
  lost <= SCORE_SLIGHT && bookMoves(index, fen).contains(san)
}

/// How fast a prepared move was, on the scale that grades its card.
public func speedTone(_ seconds: Double) -> ScoreTone {
  switch gradeForTime(seconds) {
  case .easy: return .up
  case .good: return .slight
  default: return .bad
  }
}

/// A move's time as shown: tenths under ten seconds, whole seconds past.
public func secondsText(_ seconds: Double) -> String {
  seconds < 10 ? "\(JS.toFixed(seconds, 1))s" : "\(JS.string(JS.round(seconds)))s"
}

/// How a run went on your prep, for its end screen.
public func prepSummary(_ found: Int, _ asked: Int, _ seconds: [Double], _ book: Int = 0) -> String? {
  if asked == 0 && book == 0 { return nil }
  var parts: [String] = []
  if asked > 0 {
    parts.append("Prep \(found) of \(asked)")
    if !seconds.isEmpty {
      parts.append("\(secondsText(seconds.reduce(0, +) / Double(seconds.count))) average")
      parts.append("\(seconds.filter { gradeForTime($0) == .easy }.count) fast")
    }
  }
  if book > 0 { parts.append("\(book) book move\(book == 1 ? "" : "s")") }
  return parts.joined(separator: " \u{00b7} ")
}

public enum GlowTone: String, Sendable, Codable { case green, yellow, red }

/// Who is better, as the board's glow shows it.
public struct Glow: Equatable, Sendable, Codable {
  public var tone: GlowTone
  /// 0...1, how bright.
  public var strength: Double
}

public let GLOW_PAWN: Double = 100
public let GLOW_MINOR: Double = 300
public let GLOW_SPAN: Double = 400

/// The glow for a position, from the engine's score in White's frame, or nil when level.
public func glowFor(_ color: Color, _ cp: Double) -> Glow? {
  let mine = color == .w ? cp : -cp
  if mine >= GLOW_PAWN { return Glow(tone: .green, strength: min(1, (mine - GLOW_PAWN) / GLOW_SPAN)) }
  if mine <= -GLOW_MINOR { return Glow(tone: .red, strength: 0.5 + 0.5 * min(1, (-mine - GLOW_MINOR) / GLOW_SPAN)) }
  if mine <= -GLOW_PAWN { return Glow(tone: .yellow, strength: 0.5) }
  return nil
}

/* ── points, moments, combo ── */

public let COMBO_CLEAN: Double = 20
public let COMBO_HOLD: Double = 40

/// The combo after a judged move that cost `lost` against the best.
public func comboAfter(_ streak: Int, _ lost: Double) -> Int {
  if lost <= COMBO_CLEAN { return streak + 1 }
  if lost <= COMBO_HOLD { return streak }
  return 0
}

/// What each move earns at this combo.
public func comboMultiplier(_ streak: Int) -> Int {
  if streak >= 10 { return 4 }
  if streak >= 6 { return 3 }
  if streak >= 3 { return 2 }
  return 1
}

public let MOMENT_GAP: Double = 150
public let MOMENT_FLOOR: Double = 100
public let MOMENT_FOUND: Double = 50
public let MOMENT_BONUS = 10
public let MOMENT_STREAK_BONUS = 5

private let MATE: Double = 10_000

/// Whether a position is a moment: the engine's best against its second best, White's frame.
public func isMoment(_ color: Color, _ best: Double, _ second: Double?) -> Bool {
  guard let second else { return false }
  let top = color == .w ? best : -best
  let next = color == .w ? second : -second
  if top >= MATE { return next < MATE }
  return top >= MOMENT_FLOOR && top - next >= MOMENT_GAP
}

/// The bonus for a moment found, with `streak` found in a row before it.
public func momentBonus(_ streak: Int) -> Int {
  MOMENT_BONUS + MOMENT_STREAK_BONUS * streak
}

/* ── a run ── */

/// A prepared position answered with a different, sound move.
public struct Miss: Equatable, Sendable {
  /// `played[ply]` is your move.
  public var ply: Int
  /// The position you were asked about.
  public var fen: String
  public var played: String
  public var expected: String
}

public struct SurvivalRun: Equatable, Sendable {
  public var run: Run
  /// Your own moves so far, every one the referee passed.
  public var moves: Int
  public var misses: [Miss]
  public var extras: Extras
}

public struct SurvivalStart {
  public var source: LineSource
  public var state: SurvivalRun
  public var redraw: (Run) -> Run
}

public struct StartOptions {
  public var steer: SurvivalSteer
  public var tree: OpeningTree
  public var reps: [Repertoire]
  public var node: OpeningNode
  public var color: ColorChoice
  public var weakness: Weakness?
  public var growth: GrowthOptions?
  public var holeWeight: ((Hole) -> Double)?
  public var seen: Seen?
  public var seed: Double?
  /// What My lines tilts toward. Autopilot chooses; the setup screen leans weak.
  public var lean: Steer?
  public var toward: OpeningNode?
  public var enter = false
  public var at: [String]?

  public init(steer: SurvivalSteer, tree: OpeningTree, reps: [Repertoire], node: OpeningNode, color: ColorChoice) {
    self.steer = steer
    self.tree = tree
    self.reps = reps
    self.node = node
    self.color = color
  }
}

/// Open a run. Ignore my lines draws on the book alone, your prep kept to know where you missed.
public func startSurvival(_ opts: StartOptions) -> SurvivalStart? {
  let blind = opts.steer == .book
  var begin = BeginOptions(tree: opts.tree, reps: blind ? [] : opts.reps, node: opts.node, color: opts.color)
  begin.steer = opts.steer == .gaps ? .gaps : opts.lean ?? .weak
  begin.toward = opts.toward
  begin.enter = opts.enter
  begin.at = opts.at
  begin.weakness = opts.weakness
  begin.growth = opts.growth
  begin.holeWeight = opts.holeWeight
  begin.seen = opts.seen
  begin.seed = opts.seed
  guard var begun = beginRun(begin) else { return nil }
  var source = begun.source
  if blind {
    // The opponent knows nothing of your prep, but the referee still does.
    let side = begun.run.color
    let rep = opts.reps.first { $0.color == side }
    source.prepAt = regionSource(opts.tree, opts.node, rep, side).prepAt
    begun.run.repertoireId = rep?.id
  }
  return SurvivalStart(source: source, state: SurvivalRun(run: begun.run, moves: 0, misses: [], extras: NO_EXTRAS), redraw: begun.redraw)
}

/// Your prep's answers here, best first.
public func prepHere(_ source: LineSource, _ state: SurvivalRun) -> [String] {
  source.prepAt(state.run.fen)
}

/// One of your moves, passed by your prep or the engine. A miss is logged on the run.
public func playYours(_ state: SurvivalRun, _ san: String, _ missed: String? = nil, _ extras: Extras? = nil) -> SurvivalRun {
  let run = state.run
  guard let move = applySan(run.fen, san) else { return state }
  var next = state
  next.run.target = run.played.count < run.target.count && run.target[run.played.count] == san ? run.target : []
  next.run.fen = move.after
  next.run.played.append(san)
  next.run.survived += 1
  next.moves += 1
  next.extras = extras ?? prepExtras(state.extras)
  if let missed { next.misses.append(Miss(ply: run.played.count, fen: run.fen, played: san, expected: missed)) }
  return next
}

/// The opponent's reply from the book, when there is one.
public func bookReply(_ source: LineSource, _ index: ReferenceIndex, _ state: SurvivalRun, _ rand: () -> Double) -> String? {
  let run = state.run
  if !source.weightsAt(run.fen, run.played).isEmpty {
    let next = opponentReply(source, run, rand)
    return next.played.count > run.played.count ? next.played.last : nil
  }
  let moves = lookup(index, run.fen)?.moves ?? []
  let all = moves.reduce(0) { $0 + max(0, $1.games) }
  if moves.isEmpty || all <= 0 { return nil }
  // Book moves only, where there are any.
  let common = moves.filter { $0.games / all >= BOOK_SHARE }
  let book = common.isEmpty ? moves : common
  let total = book.reduce(0) { $0 + max(0, $1.games) }
  var roll = rand() * total
  for move in book {
    roll -= max(0, move.games)
    if roll <= 0 { return move.san }
  }
  return book.last!.san
}

/// The opponent's move, whoever chose it.
public func playTheirs(_ state: SurvivalRun, _ san: String) -> SurvivalRun {
  guard let move = applySan(state.run.fen, san) else { return state }
  var next = state
  next.run.fen = move.after
  next.run.played.append(san)
  return next
}

/// The move number a ply is played on.
public func moveNumber(_ ply: Int) -> Int {
  ply / 2 + 1
}

/* ── the record ── */

public let RECENT_RUNS = 5
public let HISTORY_RUNS = 16

public struct SurvivalScore: Equatable, Sendable, Codable {
  public var best = 0
  public var recent: [Int] = []
  public var history: [Int] = []
  public var runs = 0
  /// Runs you ended yourself.
  public var ended = 0
  public var bestPoints = 0
  public init() {}
}

public struct SurvivalRecord: Equatable, Sendable, Codable {
  public var global = SurvivalScore()
  public var openings: [String: SurvivalScore] = [:]
  public init() {}
}

public let EMPTY_SURVIVAL_SCORE = SurvivalScore()

/// Every opening a line went through, and every one above those.
public func openingsAlong(_ tree: OpeningTree, _ line: [String]) -> [String] {
  var out = OrderedMap<String, Bool>()
  for fen in walkSan(line).fens {
    guard let node = tree.byKey[positionKey(fen)], node.depth > 0 else { continue }
    for above in ancestorsOf(tree, node.id) { out[above.id] = true }
  }
  return out.keys
}

private func scored(_ score: SurvivalScore?, _ moves: Int, _ points: Int) -> SurvivalScore {
  var out = score ?? SurvivalScore()
  out.best = max(out.best, moves)
  out.recent = Array((out.recent + [moves]).suffix(RECENT_RUNS))
  out.history = Array((out.history + [moves]).suffix(HISTORY_RUNS))
  out.runs += 1
  out.bestPoints = max(out.bestPoints, points)
  return out
}

/// Log a finished run against the global record and every opening it went through.
public func recordSurvival(_ record: SurvivalRecord, _ tree: OpeningTree, _ line: [String], _ moves: Int, _ points: Int? = nil) -> SurvivalRecord {
  var out = record
  for id in openingsAlong(tree, line) { out.openings[id] = scored(out.openings[id], moves, points ?? moves) }
  out.global = scored(record.global, moves, points ?? moves)
  return out
}

/// Log a run you ended yourself: counted, and nothing toward best or recent form.
public func recordEndedSurvival(_ record: SurvivalRecord, _ tree: OpeningTree, _ line: [String]) -> SurvivalRecord {
  var out = record
  for id in openingsAlong(tree, line) { out.openings[id, default: SurvivalScore()].ended += 1 }
  out.global.ended += 1
  return out
}

/// Recent form: the median of the last few runs, or nil before any.
public func recentForm(_ score: SurvivalScore?) -> Double? {
  let recent = score?.recent ?? []
  if recent.isEmpty { return nil }
  let sorted = recent.sorted()
  let mid = sorted.count / 2
  return sorted.count % 2 == 1 ? Double(sorted[mid]) : JS.round(Double(sorted[mid - 1] + sorted[mid]) / 2)
}

/// The score for an opening, or the global one for the root.
public func survivalFor(_ record: SurvivalRecord, _ id: String) -> SurvivalScore {
  id.isEmpty ? record.global : record.openings[id] ?? SurvivalScore()
}

extension SurvivalScore {
  /// A saved score missing a field is still a score: `normalizeSurvival`.
  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    self.init()
    best = try c.decodeIfPresent(Int.self, forKey: .best) ?? 0
    let recent = try c.decodeIfPresent([Int].self, forKey: .recent) ?? []
    self.recent = Array(recent.suffix(RECENT_RUNS))
    // Saves from before the history was kept start it from recent form's runs.
    history = Array((try c.decodeIfPresent([Int].self, forKey: .history) ?? recent).suffix(HISTORY_RUNS))
    runs = try c.decodeIfPresent(Int.self, forKey: .runs) ?? 0
    ended = try c.decodeIfPresent(Int.self, forKey: .ended) ?? 0
    bestPoints = try c.decodeIfPresent(Int.self, forKey: .bestPoints) ?? 0
  }
}

extension SurvivalRecord {
  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    self.init()
    global = try c.decodeIfPresent(SurvivalScore.self, forKey: .global) ?? SurvivalScore()
    openings = try c.decodeIfPresent([String: SurvivalScore].self, forKey: .openings) ?? [:]
  }
}
