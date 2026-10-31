import Book
import ChessCore
import Foundation
import Shared

/// Growth: the repertoire gets wider, one batch of answers at a time. The
/// rows and the run of `src/model/growth.ts`; the holes are in `Holes.swift`.

/// One line's tip, with the opponent to move and nothing of yours for what they play.
public struct LineEnd: Equatable, Sendable {
  public var path: [String]
  public var fen: String
  public var nodeId: String?
  public var reach: Double
}

/// One opening family with work available in it, named for where its holes lead.
public struct GrowthRow: Equatable, Sendable {
  public var id: String
  public var repertoireId: String
  public var color: Color
  public var name: String
  public var eco: String?
  /// Plies to the shallowest hole in this row.
  public var depth: Int
  /// The share of the most played hole here.
  public var topShare: Double
  public var starred: Bool
  public var urgency: Double
  public var score: Double
  public var holes: [Hole]
  public var ends: [LineEnd]
}

/// How much a star is worth against raw urgency.
public let STAR_BOOST = 1.6

/// How badly one row wants doing, 0...1: depth first, then how often, then breadth.
public func rowUrgency(_ depth: Int, _ topShare: Double, _ holes: Int) -> Double {
  let early = 1 / (1 + Double(depth) / 3)
  let played = topShare <= 0 ? 0 : topShare / (topShare + 5)
  let breadth = 1 + 0.05 * Double(min(holes - 1, 4))
  return max(0, min(1, 1.5 * early * played * breadth))
}

/// The family heading for a line: the shallowest name past the first move.
public func family(_ index: ReferenceIndex, _ sans: [String]) -> NamedLine? {
  let names = namesAlong(index, sans)
  guard var found = names.first(where: { $0.ply >= 2 }) ?? names.last else { return nil }
  found.name = familyName(index, found.name)
  return found
}

private func isStarred(_ starred: [[String]], _ sans: [String]) -> Bool {
  starred.contains { fav in !fav.isEmpty && fav.count <= sans.count && fav.indices.allSatisfy { sans[$0] == fav[$0] } }
}

/// The openings a selection puts on the lobby, by name.
private func openingsInSelection(_ tree: OpeningTree, _ node: OpeningNode) -> Set<String> {
  Set(ancestorsOf(tree, node.id).map(\.name) + descendantsOf(node).map(\.name))
}

/// What a row with nothing the book can weigh counts as, for urgency.
private let UNWEIGHED_SHARE = 0.5

/// Growth's rows for some trees, ranked by urgency.
public func growthRows(_ reps: [Repertoire], _ index: ReferenceIndex, _ opts: GrowthOptions = GrowthOptions()) -> [GrowthRow] {
  let starred = (opts.starred ?? []).map { $0.split(separator: " ").map(String.init) }
  let scoped = opts.region.flatMap { $0.node.depth > 0 ? $0 : nil }
  let offered = scoped.map { openingsInSelection($0.tree, $0.node) }
  let above = scoped.map { Set(ancestorsOf($0.tree, $0.node.id).map(\.name)) }
  func heading(_ line: [String], _ fallback: String) -> (name: String, eco: String?) {
    let named = family(index, line)
    let name = named?.name ?? fallback
    if let scoped, above!.contains(name), lineStatus(scoped.tree, scoped.node, line) == .reached {
      return (scoped.node.name, named?.eco)
    }
    return (name, named?.eco)
  }
  var rows: [GrowthRow] = []
  for rep in reps {
    var byName = OrderedMap<String, GrowthRow>()
    for hole in findHoles(rep, index, opts) {
      if opts.pastBook != true && holePastBook(index, hole) { continue }
      let line = hole.path + [hole.san]
      let (name, eco) = heading(line, holeLabel(hole))
      let id = "\(rep.id)#\(name)"
      var row = byName[id] ?? GrowthRow(
        id: id, repertoireId: rep.id, color: rep.color, name: name, eco: eco, depth: hole.path.count, topShare: 0,
        starred: false, urgency: 0, score: 0, holes: [], ends: [])
      row.depth = min(row.depth, hole.path.count)
      row.starred = row.starred || isStarred(starred, line)
      row.holes.append(hole)
      row.topShare = max(row.topShare, holeShare(hole))
      byName[id] = row
    }
    rows += byName.values.filter { offered == nil || offered!.contains($0.name) }
  }
  for i in rows.indices {
    let share = rows[i].topShare > 0 ? rows[i].topShare : UNWEIGHED_SHARE
    rows[i].urgency = rowUrgency(rows[i].depth, share, rows[i].holes.count + rows[i].ends.count)
    rows[i].score = min(1, rows[i].urgency * (rows[i].starred ? STAR_BOOST : 1))
  }
  return rows.jsSorted { a, b in
    if b.score != a.score { return b.score - a.score }
    if a.depth != b.depth { return Double(a.depth - b.depth) }
    return Double(JS.localeCompare(a.name, b.name))
  }
}

/// The row Start would begin.
public func recommended(_ rows: [GrowthRow]) -> GrowthRow? { rows.first }

/// A move the book has no name for, called after itself: "vs 1.g3".
private func holeLabel(_ hole: Hole) -> String {
  "vs \(hole.path.count / 2 + 1).\(hole.path.count % 2 == 0 ? "" : "..")\(hole.san)"
}

/* ── the run ── */

public struct GrowthRun: Equatable, Sendable {
  public var repertoireId: String
  public var color: Color
  public var rowId: String
  /// Position keys the run is aiming for.
  public var targets: Set<String>
  public var path: [String]
  public var fen: String
  public var nodeId: String?
  /// The unanswered reply the opponent has just played.
  public var hole: Hole?
}

public func startGrowth(_ rep: Repertoire, _ row: GrowthRow) -> GrowthRun {
  GrowthRun(
    repertoireId: rep.id, color: rep.color, rowId: row.id, targets: Set(row.holes.map { positionKey($0.fen) }),
    path: [], fen: rep.rootFen, nodeId: nil, hole: nil)
}

private let RARE = 0.0001

private func holeWorth(_ hole: Hole) -> Double { max(hole.reach * holeShare(hole), RARE) }

/// The hole a run should start at: the one met most often, shallower on a tie.
public func firstHole(_ row: GrowthRow) -> Hole? {
  guard var best = row.holes.first else { return nil }
  for hole in row.holes.dropFirst() where holeWorth(hole) > holeWorth(best) || (holeWorth(hole) == holeWorth(best) && hole.path.count < best.path.count) {
    best = hole
  }
  return best
}

/// The line end a row with no holes starts at.
public func firstEnd(_ row: GrowthRow) -> LineEnd? {
  guard var best = row.ends.first else { return nil }
  for end in row.ends.dropFirst() where end.reach > best.reach || (end.reach == best.reach && end.path.count < best.path.count) {
    best = end
  }
  return best
}

/// Nothing in the book for whoever is to move here.
public func pastTheBook(_ index: ReferenceIndex, _ fen: String) -> Bool {
  popularReplies(index, fen, 0).isEmpty
}

/// A hole the engine found, or one either side of which the book has nothing.
public func holePastBook(_ index: ReferenceIndex, _ hole: Hole) -> Bool {
  hole.engine || pastTheBook(index, hole.fen) || pastTheBook(index, hole.after)
}

public func startGrowthAtEnd(_ rep: Repertoire, _ row: GrowthRow, _ end: LineEnd) -> GrowthRun {
  var run = startGrowth(rep, row)
  run.path = end.path
  run.fen = end.fen
  run.nodeId = end.nodeId
  return run
}

/// A run that begins standing at a hole.
public func startGrowthAt(_ rep: Repertoire, _ row: GrowthRow, _ hole: Hole) -> GrowthRun {
  var run = startGrowth(rep, row)
  run.path = hole.path
  run.fen = hole.fen
  run.nodeId = hole.nodeId
  return enterHole(run, hole)
}

public func isUsersTurn(_ run: GrowthRun) -> Bool { fenTurn(run.fen) == run.color }

public func preparedHere(_ rep: Repertoire, _ run: GrowthRun) -> [RepMove] { childrenOf(rep, run.nodeId) }

/// Play a move the repertoire already has.
public func advance(_ rep: Repertoire, _ run: GrowthRun, _ san: String) -> GrowthRun? {
  guard let kid = preparedHere(rep, run).first(where: { $0.san == san }) else { return nil }
  var next = run
  next.path.append(kid.san)
  next.fen = kid.fenAfter
  next.nodeId = kid.id
  return next
}

private let STEER_DECAY = 0.85

/// The opponent's reply on the walk, chosen to reach the hole most worth having.
public func steer(_ rep: Repertoire, _ index: ReferenceIndex, _ run: GrowthRun, _ opts: GrowthOptions = GrowthOptions()) -> (san: String, hole: Hole?)? {
  let holes = findHoles(rep, index, opts).filter { run.targets.contains(positionKey($0.fen)) }
  let hereKey = positionKey(run.fen)
  let here = holes.filter { positionKey($0.fen) == hereKey }
  if var best = here.first {
    for hole in here.dropFirst() where holeWorth(hole) > holeWorth(best) { best = hole }
    return (best.san, best)
  }
  let kids = childrenOf(rep, run.nodeId)
  guard let firstKid = kids.first else { return nil }
  var worth: [String: Double] = [:]
  for hole in holes { worth[positionKey(hole.fen)] = max(worth[positionKey(hole.fen)] ?? 0, holeWorth(hole)) }
  var best: (kid: RepMove, value: Double)?
  for kid in kids {
    guard let value = bestBelow(rep, kid.id, worth, 0) else { continue }
    if best == nil || value > best!.value { best = (kid, value) }
  }
  return ((best?.kid ?? firstKid).san, nil)
}

private func bestBelow(_ rep: Repertoire, _ nodeId: String, _ worth: [String: Double], _ depth: Int) -> Double? {
  if depth > DEFAULT_MAX_PLY { return nil }
  guard let node = rep.nodes[nodeId] else { return nil }
  var best = worth[positionKey(node.fenAfter)].map { $0 * pow(STEER_DECAY, Double(depth)) }
  for kid in childrenOf(rep, nodeId) {
    if let found = bestBelow(rep, kid.id, worth, depth + 1), best == nil || found > best! { best = found }
  }
  return best
}

/// Step into the unanswered reply.
public func enterHole(_ run: GrowthRun, _ hole: Hole) -> GrowthRun {
  var next = run
  next.path.append(hole.san)
  next.fen = hole.after
  next.hole = hole
  return next
}

/// The run has arrived where the repertoire says nothing.
public func atHole(_ rep: Repertoire, _ run: GrowthRun) -> Bool {
  run.hole != nil || (isUsersTurn(run) && childrenOf(rep, run.nodeId).isEmpty)
}

/// Play your chosen answer. The run leaves the repertoire tree here.
public func answerHole(_ run: GrowthRun, _ san: String) -> GrowthRun? {
  guard let move = applySan(run.fen, san) else { return nil }
  var next = run
  next.path.append(san)
  next.fen = move.after
  next.hole = nil
  return next
}

/// Their most popular reply to the answer just added, as the next hole; past
/// the book the engine's best. Nil (outer) while the engine has not answered.
public func nextHole(_ index: ReferenceIndex, _ run: GrowthRun) -> Hole?? {
  let book = popularReplies(index, run.fen, 0)
  if book.isEmpty && engineReplies(run.fen) == nil { return nil }
  let reply = book.first ?? (engineReplies(run.fen) ?? []).first.map { Reply(san: $0, games: 0, white: 0, draw: 0, black: 0, share: 0, engine: true) }
  guard let reply, let after = applySan(run.fen, reply.san) else { return .some(nil) }
  return Hole(path: run.path, fen: run.fen, san: reply.san, share: reply.share, games: reply.games, after: after.after, nodeId: nil, engine: reply.engine, reach: 0)
}

/// The book's answers at a position, most played first.
public func optionsAt(_ index: ReferenceIndex, _ fen: String, _ limit: Int = 4) -> [Reply] {
  Array(popularReplies(index, fen, 0).prefix(limit))
}

/// What a run offers you at a hole; nil past the book while the engine works.
public func choicesAt(_ index: ReferenceIndex, _ fen: String, _ limit: Int = 4) -> [Reply]? {
  let book = optionsAt(index, fen, limit)
  if !book.isEmpty { return book }
  guard let engine = engineReplies(fen) else { return nil }
  return Array(engine.map { Reply(san: $0, games: 0, white: 0, draw: 0, black: 0, share: 0, engine: true) }
    .filter { (engineLoss(fen, $0.san) ?? 0) <= NEAR_BEST }
    .prefix(limit))
}

/// The best of each piece's moves among `sans`, for arrows.
public func onePerPiece(_ fen: String, _ sans: [String], _ count: Int = .max) -> [(san: String, from: String, to: String)] {
  var out: [(san: String, from: String, to: String)] = []
  var pieces = Set<String>()
  for san in sans {
    if out.count >= count { break }
    guard let move = applySan(fen, san), !pieces.contains(move.from) else { continue }
    pieces.insert(move.from)
    out.append((san, move.from, move.to))
  }
  return out
}

/// The line a chosen move writes into the repertoire.
public func lineFor(_ run: GrowthRun, _ san: String) -> [String] { run.path + [san] }

/// The run another batch would carry on from, or nil with nothing left to answer.
public func resumeAdding(_ rep: Repertoire, _ index: ReferenceIndex, _ run: GrowthRun) -> GrowthRun? {
  if atHole(rep, run) {
    let choices = choicesAt(index, run.fen, 1)
    return choices == nil || !choices!.isEmpty ? run : nil
  }
  guard let found = nextHole(index, run) else { return run }
  guard let hole = found else { return nil }
  let choices = choicesAt(index, hole.after, 1)
  return choices == nil || !choices!.isEmpty ? enterHole(run, hole) : nil
}
