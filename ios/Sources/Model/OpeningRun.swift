import Foundation
import Book
import ChessCore
import Shared

/// How a run's line is drawn and how the opponent replies: the part of
/// `src/model/openingRun.ts` Survival and Autopilot use.

/// What a run knows about a position: what keeps it alive, how likely each
/// reply is, and what your prep says.
public struct LineSource: @unchecked Sendable {
  /// Named after the region the run was drawn from.
  public var label: String
  public var color: Color
  public var node: OpeningNode
  /// Moves that keep the run alive from this position, best first.
  public var movesAt: (_ fen: String, _ played: [String]) -> [String]
  /// Relative likelihood of each opponent reply.
  public var weightsAt: (_ fen: String, _ played: [String]) -> [(san: String, weight: Double)]
  /// Your own prepared moves here, preferred first.
  public var prepAt: (_ fen: String) -> [String]
}

/// One repertoire indexed by position, the opponent's moves included.
public func prepIndex(_ rep: Repertoire?) -> [String: [String]] {
  var byPosition: [String: [String]] = [:]
  guard let rep else { return byPosition }
  func visit(_ nodeId: String?) {
    let key = positionKey(fenAt(rep, nodeId))
    let kids = childrenOf(rep, nodeId)
    var list = byPosition[key] ?? []
    for kid in kids.jsSorted({ a, b in Double((b.preferred ? 1 : 0) - (a.preferred ? 1 : 0)) }) where !list.contains(kid.san) {
      list.append(kid.san)
    }
    byPosition[key] = list
    for kid in kids { visit(kid.id) }
  }
  visit(nil)
  return byPosition
}

/// Prepared or theory, inside the region. `rep` is nil when nothing is prepared for the side.
public func regionSource(_ tree: OpeningTree, _ node: OpeningNode, _ rep: Repertoire?, _ color: Color) -> LineSource {
  let index = tree.index
  let prep = prepIndex(rep)
  let approach = node.depth == 0 ? nil : approachKeys(tree, node)
  let region = node.depth == 0 ? nil : regionOf(tree, node)

  /// Every move that can be played here, prep first, then the book by popularity.
  func candidates(_ fen: String, _ played: [String]) -> [(san: String, games: Double, prepared: Bool)] {
    let status = lineStatus(tree, node, played)
    if status == .outside { return [] }
    let mine = prep[positionKey(fen)] ?? []
    let book = (lookup(index, fen)?.moves ?? []).jsSorted { cmp($1.games, $0.games) }
    var games: [String: Double] = [:]
    for move in book { games[move.san] = move.games }
    var out: [(san: String, games: Double, prepared: Bool)] = mine.map { ($0, games[$0] ?? 0, true) }
    for move in book where !mine.contains(move.san) { out.append((move.san, max(1, move.games), false)) }
    let inside: [(san: String, games: Double, prepared: Bool)]
    if status == .reached || approach == nil {
      inside = out
    } else {
      // Still on the way in: only moves the book can reach the opening from.
      inside = out.filter { move in
        guard let applied = applySan(fen, move.san) else { return false }
        let after = positionKey(applied.after)
        return after == node.key || approach!.contains(after)
      }
    }
    let scale = max(1, inside.reduce(0) { $0 + $1.games })
    let shares = withFloor(inside.map(\.games), inside.map(\.prepared))
    return inside.enumerated().map { ($0.element.san, shares[$0.offset] * scale, $0.element.prepared) }
  }

  return LineSource(
    label: node.name, color: color, node: node,
    movesAt: { fen, played in candidates(fen, played).map(\.san) },
    weightsAt: { fen, played in
      // The opponent plays book moves and your prepared replies, not every rare try.
      let all = candidates(fen, played)
      let entry = lookup(index, fen)
      let total = totalGamesAt(entry)
      let shareOf = { (san: String) -> Double in
        total > 0 ? (entry?.moves.first { $0.san == san }?.games ?? 0) / total : 0
      }
      let picked = all.filter { $0.prepared || shareOf($0.san) >= BOOK_SHARE }
      return (picked.isEmpty ? all : picked).map { ($0.san, $0.games) }
    },
    prepAt: { fen in
      let key = positionKey(fen)
      let mine = prep[key] ?? []
      guard let region, !region.inside.contains(key), region.approach.contains(key) else { return mine }
      // On the way in, only prep that can still reach the opening is prep for it.
      return mine.filter { san in
        guard let after = applySan(fen, san) else { return false }
        let next = positionKey(after.after)
        return region.inside.contains(next) || region.approach.contains(next)
      }
    })
}

/// How often each line of a repertoire should come up, as a weight per tip:
/// by the book where the opponent chooses, evenly where you do. Empty without a book.
public func lineOdds(_ rep: Repertoire, _ side: Color, _ index: ReferenceIndex?, _ eligible: Set<String>? = nil) -> OrderedMap<String, Double> {
  var odds = OrderedMap<String, Double>()
  guard let index else { return odds }
  let wanted = { (tipId: String) in eligible == nil || eligible!.contains(tipId) }

  var reachable: [String: Bool] = [:]
  func leadsSomewhere(_ nodeId: String?) -> Bool {
    let key = nodeId ?? ""
    if let seen = reachable[key] { return seen }
    let kids = childrenOf(rep, nodeId)
    let ok = kids.isEmpty ? nodeId != nil && wanted(nodeId!) : kids.contains { leadsSomewhere($0.id) }
    reachable[key] = ok
    return ok
  }

  func splits(_ fen: String, _ kids: [RepMove]) -> [Double] {
    let even = kids.map { _ in 1 / Double(kids.count) }
    if kids.count < 2 || fenTurn(fen) == side { return even }
    guard let entry = lookup(index, fen), entry.moves.count >= 2 else { return even }
    let total = entry.moves.reduce(0) { $0 + $1.games }
    if total <= 0 { return even }
    var games: [String: Double] = [:]
    for m in entry.moves { games[m.san] = m.games }
    return withFloor(kids.map { games[$0.san] ?? 0 }, kids.map { _ in true })
  }

  func visit(_ nodeId: String?, _ weight: Double) {
    let kids = childrenOf(rep, nodeId).filter { leadsSomewhere($0.id) }
    if kids.isEmpty {
      if let nodeId, wanted(nodeId) { odds[nodeId] = weight }
      return
    }
    let shares = splits(fenAt(rep, nodeId), kids)
    let sum = shares.reduce(0, +)
    let total = sum == 0 ? 1 : sum
    for (i, kid) in kids.enumerated() { visit(kid.id, weight * shares[i] / total) }
  }
  if leadsSomewhere(nil) { visit(nil, 1) }
  return odds
}

/// What a Run's opponent steers toward.
public enum Steer: String, Sendable { case popular, weak, gaps }

/// How much less often a hole may be met than the best one and still be drawn.
public let DRAW_WINDOW: Double = 8

/// A run's board and the line steered toward. The parts of the prototype's
/// `Run` that Survival reads.
public struct Run: Equatable, Sendable {
  public var id: String
  public var sourceLabel: String
  /// The region the run was drawn in.
  public var openingId: String
  public var repertoireId: String?
  public var bookRun: Bool
  public var color: Color
  public var fen: String
  public var played: [String]
  public var survived: Int
  public var over: Bool
  /// Remaining moves of the line drawn, driving opponent replies.
  public var target: [String]
  /// The line drawn, kept whole.
  public var drawn: [String]
  /// Plies played for you before the run began.
  public var opened: Int
  /// The opening the run was started inside, or nil from move one.
  public var enteredIn: String?
}

nonisolated(unsafe) private var runCounter = 0

private func newRunId() -> String {
  runCounter += 1
  return "run\(runCounter)-\(String(Int64(Env.now()), radix: 36))"
}

/// How badly each position wants practice, by repertoire and position.
public typealias Weakness = (_ repertoireId: String, _ key: String) -> Double

/// A game of yours that went off prep at a position: what `weaknessFromCards` reads of Repair.
public struct Slip: Sendable {
  public var kind: String
  public var repertoireId: String
  public var key: String
  public var games: Int
  public init(kind: String, repertoireId: String, key: String, games: Int) {
    self.kind = kind
    self.repertoireId = repertoireId
    self.key = key
    self.games = games
  }
}

/// The review schedule as a practice appetite.
public func weaknessFromCards(_ cards: [String: Card], _ slips: [Slip] = [], _ now: Double = Env.now()) -> Weakness {
  var slipped: [String: Int] = [:]
  for item in slips where item.kind == "offprep" { slipped[cardId(item.repertoireId, item.key), default: 0] += item.games }
  return { repertoireId, key in
    let id = cardId(repertoireId, key)
    let evidence = 2 * Double(min(3, slipped[id] ?? 0))
    // Never studied: worth seeing, but not the emergency a lapse is.
    guard let card = cards[id] else { return 1.5 + evidence }
    var score = 1 + evidence
    score += Double(card.lapses) * 1.2
    score += max(0, 2.5 - card.ease) * 2
    if card.stage == .learning { score += 1 }
    if card.due <= now { score += 1 }
    let answered = card.correct + card.incorrect
    if answered > 0 { score += Double(card.incorrect) / Double(answered) * 2 }
    return score
  }
}

/// The mean appetite over the positions a line asks you about.
public func lineWeakness(_ repertoireId: String, _ keys: [String], _ weakness: Weakness) -> Double {
  if keys.isEmpty { return 1 }
  return keys.reduce(0) { $0 + weakness(repertoireId, $1) } / Double(keys.count)
}

func pickWeighted<T>(_ items: [T], _ weight: (T) -> Double, _ rand: () -> Double) -> T {
  let total = items.reduce(0) { $0 + max(0, weight($1)) }
  if total <= 0 { return items[Int((rand() * Double(items.count)).rounded(.down))] }
  var roll = rand() * total
  for item in items {
    roll -= max(0, weight(item))
    if roll <= 0 { return item }
  }
  return items[items.count - 1]
}

public struct BeginOptions {
  public var tree: OpeningTree
  public var reps: [Repertoire]
  /// The region to run in.
  public var node: OpeningNode
  /// An opening inside the region to walk toward.
  public var toward: OpeningNode?
  public var color: ColorChoice
  public var steer: Steer = .popular
  public var seed: Double?
  /// Skip lines that ask fewer than this many moves.
  public var minDecisions = 4
  public var weakness: Weakness?
  public var growth: GrowthOptions?
  public var holeWeight: ((Hole) -> Double)?
  public var seen: Seen?
  /// Start inside the opening walked toward.
  public var enter = false
  /// Start at the position these moves reach.
  public var at: [String]?

  public init(tree: OpeningTree, reps: [Repertoire], node: OpeningNode, color: ColorChoice) {
    self.tree = tree
    self.reps = reps
    self.node = node
    self.color = color
  }
}

public struct Begun {
  public var source: LineSource
  public var run: Run
  /// Draw a new line from where the run has got to, by the same steer.
  public var redraw: (Run) -> Run
}

private struct At {
  var fen: String
  var played: [String]
}

private struct Drawn {
  var target: [String]
  var gap: Hole?
  var firstLine: Bool
}

/// A run in a region: the source, and the run with its line drawn.
public func beginRun(_ opts: BeginOptions) -> Begun? {
  let rand = mulberry32(seed: opts.seed ?? (Env.random() * 2_147_483_648).rounded(.down))
  let side = resolveColor(opts.color, rand)
  let tree = opts.tree, node = opts.node
  guard let rootMoves = lookup(tree.index, START_FEN)?.moves, !rootMoves.isEmpty else { return nil }
  let rep = opts.reps.first { $0.color == side }
  let source = regionSource(tree, node, rep, side)
  let aim = opts.toward ?? node
  let steer = opts.steer

  func draw(_ at: At) -> Drawn {
    let atStart = at.played.isEmpty
    let onWay = aim.sans.count > at.played.count && at.played.indices.allSatisfy { aim.sans[$0] == at.played[$0] }
    let fallback = onWay ? aim.sans : []
    let through = rep.map { linesThrough($0, tree, aim, side, at) } ?? []
    let firstLine = rep != nil && steer == .gaps && atStart && through.isEmpty && aim.depth > 0
    let gap = rep != nil && steer == .gaps && !firstLine ? drawHole(rep!, tree, aim, opts, rand, at) : nil
    if let gap { return Drawn(target: at.played + gap.rest, gap: gap.hole, firstLine: firstLine) }
    guard let rep, !firstLine, !through.isEmpty else { return Drawn(target: fallback, gap: nil, firstLine: firstLine) }
    let weakness = steer == .weak ? opts.weakness : nil
    let long = through.filter { $0.keys.count >= opts.minDecisions }
    let usable = long.isEmpty ? through : long
    // Never the same line twice running, while there is another.
    let seen = opts.seen ?? NOTHING_SEEN
    let rested = usable.filter { !justRun(seen, rep, $0.tipId) }
    let field = rested.isEmpty ? usable : rested
    let odds = lineOdds(rep, side, tree.index, Set(field.map(\.tipId)))
    let even = odds.isEmpty
    let line = pickWeighted(field, { l in
      (even ? 1 : odds[l.tipId] ?? 0)
        * (weakness.map { lineWeakness(rep.id, l.keys, $0) } ?? 1)
        * max(lineStaleness(seen, rep, l.tipId), 0.02)
    }, rand)
    return Drawn(target: line.sans, gap: nil, firstLine: firstLine)
  }

  // A round started at a position: the moves to it are played for you.
  let atWalk = (opts.at?.isEmpty == false) ? walkSan(opts.at!) : nil
  let atFen = atWalk.flatMap { $0.moves.count == opts.at!.count ? $0.fens[opts.at!.count] : nil }
  let first = atFen.map { draw(At(fen: $0, played: opts.at!)) } ?? draw(At(fen: START_FEN, played: []))
  // A round started inside the opening: the drawn line's way in is played for you.
  let way = atFen != nil ? opts.at! : opts.enter && aim.depth >= 2 ? wayIn(tree, aim, first.target) : []
  let entered = walkSan(way)
  let opened = entered.moves.count == way.count ? way.count : 0
  let fen = opened < entered.fens.count ? entered.fens[opened] : START_FEN
  let startedIn = opened == 0 ? nil : atFen != nil ? deepestNodeWithin(tree, aim, way) : aim

  let run = Run(
    id: newRunId(), sourceLabel: startedIn?.name ?? node.name, openingId: node.id, repertoireId: rep?.id,
    bookRun: rep == nil || linesThrough(rep!, tree, aim, side, At(fen: START_FEN, played: [])).isEmpty,
    color: side, fen: fen, played: Array(way.prefix(opened)), survived: 0, over: false,
    target: first.target, drawn: first.target, opened: opened,
    enteredIn: startedIn.flatMap { $0.depth > 0 ? $0.id : nil })

  let redraw = { (current: Run) -> Run in
    let next = draw(At(fen: current.fen, played: current.played))
    if next.target.count <= current.played.count { return current }
    var out = current
    out.target = next.target
    out.drawn = next.target
    return out
  }
  return Begun(source: source, run: run, redraw: redraw)
}

/// Your lines through the opening that pass through a position, each whole
/// with the moves played so far first, and the positions it still asks.
private func linesThrough(_ rep: Repertoire, _ tree: OpeningTree, _ aim: OpeningNode, _ side: Color, _ at: At) -> [(tipId: String, sans: [String], keys: [String])] {
  let key = positionKey(at.fen)
  var out: [(tipId: String, sans: [String], keys: [String])] = []
  for line in leafLines(rep) where lineStatus(tree, aim, line.sans) == .reached {
    let path = pathTo(rep, line.tipId)
    guard let from = path.firstIndex(where: { $0.key == key }) else { continue }
    let rest = path[from...]
    out.append((line.tipId, at.played + rest.map(\.san), rest.filter { fenTurn($0.fenBefore) == side }.map(\.key)))
  }
  return out
}

/// The way into an opening along a line: its moves up to the first that
/// reaches a position the opening names; empty when it never gets there.
public func wayIn(_ tree: OpeningTree, _ aim: OpeningNode, _ sans: [String]) -> [String] {
  if aim.depth == 0 { return [] }
  let inside = regionOf(tree, aim).inside
  var fen = START_FEN
  for (i, san) in sans.enumerated() {
    guard let move = applySan(fen, san) else { return [] }
    fen = move.after
    if inside.contains(positionKey(fen)) { return Array(sans.prefix(i + 1)) }
  }
  return []
}

/// The hole to walk toward: inside the opening while there is any, drawn on
/// how often you would meet it and how much of the round would be new.
private func drawHole(_ rep: Repertoire, _ tree: OpeningTree, _ aim: OpeningNode, _ opts: BeginOptions, _ rand: () -> Double, _ at: At) -> (hole: Hole, rest: [String])? {
  let key = positionKey(at.fen)
  var growth = opts.growth ?? GrowthOptions()
  growth.region = (tree, aim)
  let found: [(hole: Hole, rest: [String])] = findHoles(rep, tree.index, growth).compactMap { hole in
    let from = at.played.isEmpty ? 0 : (keysAlong(hole.path).firstIndex(of: key) ?? -1) + 1
    if !at.played.isEmpty && from == 0 { return nil }
    return (hole, Array(hole.path[from...]) + [hole.san])
  }
  if found.isEmpty { return nil }
  let inside = found.filter { lineStatus(tree, aim, $0.hole.path + [$0.hole.san]) == .reached }
  let holes = inside.isEmpty ? found : inside
  let evidence = opts.holeWeight ?? { _ in 1 }
  let seen = opts.seen ?? NOTHING_SEEN
  func fresh(_ hole: Hole) -> Double {
    let walk = keysAlong(hole.path).map { staleness(seen, $0) }
    let added = Double(2 * movesToFit(hole.path.count, opts.growth?.maxPly ?? 18))
    return pow((walk.reduce(0, +) + added) / (Double(walk.count) + added), 2)
  }
  let met = { (h: (hole: Hole, rest: [String])) in h.hole.reach * holeShare(h.hole) * evidence(h.hole) * fresh(h.hole) }
  let best = holes.map(met).max()!
  let field = holes.filter { met($0) * DRAW_WINDOW >= best }
  return pickWeighted(field.isEmpty ? holes : field, met, rand)
}

/// Resolve "random" once, up front.
public func resolveColor(_ color: ColorChoice, _ rand: () -> Double) -> Color {
  switch color {
  case .random: return rand() < 0.5 ? .w : .b
  case .w: return .w
  case .b: return .b
  }
}

/// The opponent's reply: the drawn line where it still applies, else weighted.
public func opponentReply(_ source: LineSource, _ run: Run, _ rand: () -> Double) -> Run {
  let onLine = run.played.count < run.target.count ? run.target[run.played.count] : nil
  let options = source.weightsAt(run.fen, run.played)
  var out = run
  if options.isEmpty {
    out.over = true
    return out
  }
  var san = onLine.flatMap { source.movesAt(run.fen, run.played).contains($0) ? $0 : nil }
  if san == nil {
    // Prefer replies the source can still answer.
    let live = options.filter { o in
      guard let move = applySan(run.fen, o.san) else { return false }
      return !source.movesAt(move.after, run.played + [o.san]).isEmpty
    }
    let pool = live.isEmpty ? options : live
    let total = pool.reduce(0) { $0 + $1.weight }
    var roll = rand() * total
    san = pool[pool.count - 1].san
    for option in pool {
      roll -= option.weight
      if roll <= 0 {
        san = option.san
        break
      }
    }
  }
  guard let move = applySan(run.fen, san!) else {
    out.over = true
    return out
  }
  out.fen = move.after
  out.played.append(san!)
  return out
}

/// How much a move cost, in centipawns from your side; both scores in White's frame.
public func evalLoss(_ color: Color, _ before: Double, _ after: Double) -> Double {
  color == .w ? before - after : after - before
}

public struct EvalVerdict: Equatable, Sendable, Codable {
  public var ok: Bool
  /// Centipawns dropped, never negative.
  public var lost: Double
}

/// Judge a move past the prep: over the limit is a blunder.
public func judgeByEval(_ color: Color, _ before: Double, _ after: Double, _ limit: Double = BLUNDER_LIMIT) -> EvalVerdict {
  let lost = max(0, evalLoss(color, before, after))
  return EvalVerdict(ok: lost <= limit, lost: lost)
}

/// How the line would have gone on from here.
public func continuation(_ source: LineSource, _ run: Run, _ plies: Int = 48) -> [String] {
  var out: [String] = []
  var fen = run.fen
  var played = run.played
  for _ in 0..<plies {
    let onLine = played.count < run.target.count ? run.target[played.count] : nil
    let options = source.movesAt(fen, played)
    guard let first = options.first else { break }
    let san = onLine.flatMap { options.contains($0) ? $0 : nil } ?? first
    guard let move = applySan(fen, san) else { break }
    out.append(san)
    played.append(san)
    fen = move.after
  }
  return out
}
