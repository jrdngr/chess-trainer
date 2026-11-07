import Book
import ChessCore
import Foundation
import Shared

/// The recommendation engine: what the app suggests next. Each question is
/// its own function. Every answer is computed from the data passed in, with
/// deterministic tie-breakers, and none of them carries wording: callers word
/// things. The book is the only source for gaps; game history only counts
/// runs.

/* ── gaps ── */

/// Why a line is recommended.
public enum GapKind: String, Sendable, Codable {
  /// A common reply you have no answer to, where you answer others.
  case noAnswer
  /// Your line ends before the opening the book names does.
  case tooShort
}

/// A common opponent reply in your Playbook with no answer from you.
public struct Gap: Equatable, Sendable {
  public var kind: GapKind
  public var repertoireId: String
  public var color: Color
  /// The reply, with where it is played from.
  public var hole: Hole
  /// The reply's share at its position, in percent.
  public var share: Double { hole.share }
  /// reach × share × depth bias.
  public var importance: Double
  /// The book's deepest name on the line through the reply.
  public var name: String
  /// Your moves still missing to the end of the named opening, at least 1.
  public var missing: Int
  /// The moves to the reply, the reply included.
  /// The first move of a game with nothing saved has no reply: its line is the path alone.
  public var line: [String] { hole.san.isEmpty ? hole.path : hole.path + [hole.san] }
  /// Plies of the line that are yours and already in the Playbook.
  public var path: [String] { hole.path }
  public var id: String { "\(repertoireId)#\(line.joined(separator: " "))" }
}

/// The least share a reply needs to be a gap, in percent.
public let GAP_SHARE = BOOK_SHARE * 100
/// The least importance a gap needs: met in at least this share of your
/// games, after the depth discount. Rarer replies are not worth recommending.
public let GAP_MIN_IMPORTANCE = 0.02
/// Each full move of depth makes a gap this much less important.
public let GAP_DEPTH_BIAS = 0.85
/// How deep gaps are looked for, in plies.
private let GAP_MAX_PLY = 40
/// How far a line is followed to find where its named opening ends.
private let NAMED_LOOKAHEAD = 30

/// Where the named opening along a line ends: the deepest ply the book names,
/// following the most played move once the line runs out, and that name.
public func namedEnd(_ index: ReferenceIndex, _ line: [String]) -> (ply: Int, name: String)? {
  var fen = START_FEN
  var best: (ply: Int, name: String)? = index.names[positionKey(fen)].map { (0, $0.name) }
  var ply = 0
  for san in line {
    guard let move = applySan(fen, san) else { return best }
    fen = move.after
    ply += 1
    if let named = index.names[positionKey(fen)] { best = (ply, named.name) }
  }
  for _ in 0..<NAMED_LOOKAHEAD {
    guard let entry = lookup(index, fen), let top = entry.moves.max(by: { $0.games < $1.games }),
      let move = applySan(fen, top.san)
    else { break }
    fen = move.after
    ply += 1
    if let named = index.names[positionKey(fen)] { best = (ply, named.name) }
  }
  return best
}

/// The importance of a reply: how often you meet it, discounted by depth.
public func gapImportance(reach: Double, share: Double, plies: Int) -> Double {
  reach * share / 100 * pow(GAP_DEPTH_BIAS, Double(plies / 2))
}

/// Every gap in some sides' Playbooks, most important first. `scope` keeps
/// only replies inside an opening; `favorites` breaks ties.
public func gaps(_ reps: [Repertoire], _ index: ReferenceIndex, tree: OpeningTree? = nil, scope: OpeningNode? = nil, favorites: [OpeningNode] = []) -> [Gap] {
  var out: [Gap] = []
  for rep in reps where !rep.nodes.isEmpty {
    let region = tree.flatMap { t in scope.flatMap { $0.depth > 0 ? (tree: t, node: $0) : nil } }
    let holes = findHoles(rep, index, GrowthOptions(minShare: GAP_SHARE, maxPly: GAP_MAX_PLY, region: region))
    var shortAt = Set<String>()
    for hole in holes where !hole.engine && hole.share >= GAP_SHARE {
      let line = hole.path + [hole.san]
      guard let end = namedEnd(index, line), end.ply >= line.count else { continue }
      let answered = childrenOf(rep, hole.nodeId).contains { !childrenOf(rep, $0.id).isEmpty }
      let kind: GapKind = hole.path.isEmpty || answered ? .noAnswer : .tooShort
      // A line that just stops is one gap, at its most played reply.
      if kind == .tooShort && !shortAt.insert(positionKey(hole.fen)).inserted { continue }
      let importance = gapImportance(reach: hole.reach, share: hole.share, plies: hole.path.count)
      guard importance >= GAP_MIN_IMPORTANCE else { continue }
      let name = deepestName(index, line)?.name ?? end.name
      out.append(Gap(
        kind: kind, repertoireId: rep.id, color: rep.color, hole: hole, importance: importance,
        name: name, missing: max(1, (end.ply - line.count + 1) / 2)))
    }
  }
  return rankGaps(out, tree: tree, favorites: favorites)
}

/// Gaps by importance; ties go shallower first, then inside a favorite,
/// then White before Black, then by the line's moves.
public func rankGaps(_ list: [Gap], tree: OpeningTree?, favorites: [OpeningNode]) -> [Gap] {
  func favored(_ gap: Gap) -> Bool {
    guard let tree else { return false }
    return favorites.contains { lineStatus(tree, $0, gap.line) == .reached }
  }
  return list.jsSorted { a, b in
    if a.importance != b.importance { return b.importance - a.importance }
    if a.line.count != b.line.count { return Double(a.line.count - b.line.count) }
    let fa = favored(a), fb = favored(b)
    if fa != fb { return fa ? -1 : 1 }
    if a.color != b.color { return a.color == .w ? -1 : 1 }
    return Double(JS.localeCompare(a.line.joined(separator: " "), b.line.joined(separator: " ")))
  }
}

/// A short list of gaps: `quota` of each kind first, as many as there are,
/// then the most important of the rest up to `limit`, grouped by kind in
/// rank order. Home asks for 3 with one of each kind; More for 10 with 5
/// "Too short".
public func topGaps(_ ranked: [Gap], limit: Int = 3, quota: [GapKind: Int] = [.noAnswer: 1, .tooShort: 1]) -> [Gap] {
  var picked: [Gap] = []
  for kind in [GapKind.noAnswer, .tooShort] {
    for gap in ranked.filter({ $0.kind == kind }).prefix(quota[kind] ?? 0) where picked.count < limit { picked.append(gap) }
  }
  for gap in ranked where picked.count < limit && !picked.contains(where: { $0.id == gap.id }) { picked.append(gap) }
  return [GapKind.noAnswer, .tooShort].flatMap { kind in
    ranked.filter { gap in gap.kind == kind && picked.contains { $0.id == gap.id } }
  }
}

/// The longer list behind Home's More.
public func moreGaps(_ ranked: [Gap]) -> [Gap] {
  topGaps(ranked, limit: 10, quota: [.tooShort: 5])
}

/* ── filling a gap ── */

/// Whether a fill has come to its end after your latest move: it has added
/// `size` moves, the named opening is over, or no reply is common enough.
public func fillEnds(_ index: ReferenceIndex, _ line: [String], added: Int, size: Int) -> Bool {
  if added >= size { return true }
  guard let end = namedEnd(index, line), end.ply > line.count else { return true }
  let walked = walkSan(line)
  guard walked.moves.count == line.count else { return true }
  return popularReplies(index, walked.fens[line.count], GAP_SHARE).isEmpty
}

/// The gap a line reaches with its last move, if it is one.
public func gapAt(_ ranked: [Gap], color: Color, line: [String]) -> Gap? {
  guard let last = line.last else { return nil }
  let walked = walkSan(Array(line.dropLast()))
  guard walked.moves.count == line.count - 1 else { return nil }
  let key = positionKey(walked.fens[line.count - 1])
  return ranked.first { $0.color == color && $0.hole.san == last && positionKey($0.hole.fen) == key }
}

/* ── pace, mastery and the yes or no at a hole ── */

/// When anything was last added to a Playbook, from any source.
public func lastAddedAt(_ reps: [Repertoire]) -> Double {
  reps.flatMap { $0.nodes.values.map(\.addedAt) }.max() ?? 0
}

/// Autopilot runs played since anything was added to the Playbook.
public func runsSinceAdded(_ games: [GameRecord], _ reps: [Repertoire]) -> Int {
  let since = lastAddedAt(reps)
  return games.filter { $0.mode == .autopilot && $0.at > since }.count
}

/// How due a new move is: runs since the last one, over the fill size.
public func pace(runs: Int, size: Int) -> Double {
  Double(runs) / Double(max(1, size))
}

/// How well one position is known, 0...1: right answers, more so when fast.
/// A position never asked counts as not known.
public func positionMastery(_ card: Card?) -> Double {
  guard let card, card.correct + card.incorrect > 0 else { return 0 }
  let right = Double(card.correct) / Double(card.correct + card.incorrect)
  let fast = max(0, min(1, (card.ease - 1.3) / (DEFAULT_SRS.startingEase - 1.3)))
  return right * (0.6 + 0.4 * fast)
}

/// How well you know a line up to a hole: the average over your moves on it.
/// A line with no moves of yours yet counts as known.
public func lineMastery(_ rep: Repertoire, _ cards: [String: Card], _ path: [String]) -> Double {
  let walked = walkSan(path)
  var scores: [Double] = []
  for i in path.indices where i < walked.moves.count && fenTurn(walked.fens[i]) == rep.color {
    scores.append(positionMastery(cards[cardId(rep.id, positionKey(walked.fens[i]))]))
  }
  return scores.isEmpty ? 1 : scores.reduce(0, +) / Double(scores.count)
}

/// Whether a line needs a new move now: pace × mastery² × gap ≥ 1.
public func needsNewMove(pace: Double, mastery: Double, gap: Double) -> Bool {
  pace * mastery * mastery * gap >= 1
}

/// How a hole weighs against the top gap, 0...1.
public func gapWeight(_ gap: Gap, top: Gap?) -> Double {
  guard let top, top.importance > 0 else { return 1 }
  return max(0, min(1, gap.importance / top.importance))
}

/// p × m² × g for a gap: what steering and the question at a hole weigh.
public func growScore(_ gap: Gap, top: Gap?, pace p: Double, reps: [Repertoire], cards: [String: Card]) -> Double {
  guard let rep = reps.first(where: { $0.id == gap.repertoireId }) else { return 0 }
  let m = lineMastery(rep, cards, gap.path)
  return p * m * m * gapWeight(gap, top: top)
}

/* ── the questions, on the app's state ── */

/// The gaps inside a selection, every side it covers.
public func selectionGaps(_ state: AppState, _ tree: OpeningTree, _ selection: Selection) -> [Gap] {
  let reps = state.repertoireList
  let favs = favoritesIn(tree, state.settings.favoriteOpenings, .random).map(\.node)
  var out: [Gap] = []
  for region in regionsBySide(tree, selection, state.settings.favoriteOpenings) {
    let side = reps.filter { $0.color == region.side }
    out += gaps(side, tree.index, tree: tree, scope: region.node, favorites: favs)
  }
  var seen = Set<String>()
  return rankGaps(out.filter { seen.insert($0.id).inserted }, tree: tree, favorites: favs)
}

/// Every gap in the Playbook, for Home: the selection plays no part.
public func playbookGaps(_ state: AppState, _ tree: OpeningTree) -> [Gap] {
  let favs = favoritesIn(tree, state.settings.favoriteOpenings, .random).map(\.node)
  return gaps(state.repertoireList, tree.index, tree: tree, favorites: favs)
}

/// The answer at a hole in a run: whether the line needs a new move now.
public func growAtHole(_ state: AppState, _ tree: OpeningTree, _ selection: Selection, color: Color, line: [String]) -> (gap: Gap, yes: Bool)? {
  let ranked = selectionGaps(state, tree, selection)
  let all = ranked.isEmpty ? playbookGaps(state, tree) : ranked
  guard let gap = gapAt(all, color: color, line: line) ?? gapAt(playbookGaps(state, tree), color: color, line: line) else { return nil }
  let reps = state.repertoireList
  let p = pace(runs: runsSinceAdded(state.games, reps), size: state.settings.movesPerFill)
  return (gap, growScore(gap, top: all.first, pace: p, reps: reps, cards: state.cards) >= 1)
}

/// The gap the next run steers toward when a new move is due, if any.
public func steerGap(_ state: AppState, _ tree: OpeningTree, _ selection: Selection) -> Gap? {
  let reps = state.repertoireList
  let p = pace(runs: runsSinceAdded(state.games, reps), size: state.settings.movesPerFill)
  if p < 1 { return nil }
  let ranked = selectionGaps(state, tree, selection)
  guard let top = ranked.first else { return nil }
  var best: (gap: Gap, score: Double)?
  for gap in ranked {
    let score = growScore(gap, top: top, pace: p, reps: reps, cards: state.cards)
    if score >= 1 && (best == nil || score > best!.score) { best = (gap, score) }
  }
  return best?.gap
}

/// A gap as Growth's one row, so a sitting can start on its reply.
public func gapRow(_ gap: Gap) -> GrowthRow {
  GrowthRow(
    id: gap.id, repertoireId: gap.repertoireId, color: gap.color, name: gap.name, eco: nil, depth: gap.path.count,
    topShare: gap.share, starred: false, urgency: 0, score: 0, holes: [gap.hole], ends: [])
}
