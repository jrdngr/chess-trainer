import Book
import ChessCore
import Shared

/// Freeform: every run from move one, and any of your lines is yours to play.
/// The opponent has no line drawn. At each of its turns it weighs the replies
/// that stay in your lines by how much the lines past them need practice, times
/// how often strong players choose them. Your pick on Home only steers the
/// opponent toward that opening; you can leave it at any move.

/// How much more a reply weighs when it leads toward a gap that is due a new move.
public let DUE_GAP_BOOST: Double = 6

/// How much each line of a playbook needs practice, by tip: how weak its
/// positions are, times how long it has been left.
func lineNeeds(_ rep: Playbook, _ side: Color, weakness: Weakness?, seen: Seen) -> [String: Double] {
  var out: [String: Double] = [:]
  for line in leafLines(rep) {
    let keys = pathTo(rep, line.tipId).filter { fenTurn($0.fenBefore) == side }.map(\.key)
    let weak = weakness.map { lineWeakness(rep.id, keys, $0) } ?? 1
    out[line.tipId] = weak * max(lineStaleness(seen, rep, line.tipId), 0.02)
  }
  return out
}

/// The mean need of the lines through each position of a playbook, by position key.
func positionNeeds(_ rep: Playbook, _ lines: [String: Double]) -> [String: Double] {
  var sum: [String: Double] = [:]
  var count: [String: Double] = [:]
  for (tipId, need) in lines {
    var seen = Set<String>()
    for move in pathTo(rep, tipId) {
      let after = positionKey(move.fenAfter)
      guard seen.insert(after).inserted else { continue }
      sum[after, default: 0] += need
      count[after, default: 0] += 1
    }
  }
  var out: [String: Double] = [:]
  for (key, total) in sum { out[key] = total / count[key]! }
  return out
}

/// What a Freeform run plays from: your whole playbook for the side, the
/// opponent weighing its replies at every turn. `node` is the opening picked on
/// Home (the root for Any Opening); `due` are the lines of gaps due a new move.
public func freeformSource(
  _ tree: OpeningTree, _ node: OpeningNode, _ rep: Playbook?, _ color: Color,
  weakness: Weakness?, seen: Seen, due: [[String]]
) -> LineSource {
  let index = tree.index
  let prep = prepIndex(rep)
  let needs = rep.map { positionNeeds($0, lineNeeds($0, color, weakness: weakness, seen: seen)) } ?? [:]
  let headed = node.depth > 0

  func needAfter(_ fen: String, _ san: String) -> Double {
    guard let after = applySan(fen, san) else { return 1 }
    return needs[positionKey(after.after)] ?? 1
  }

  /// Your moves here, the ones whose lines need practice most first.
  func ranked(_ fen: String) -> [String] {
    let mine = prep[positionKey(fen)] ?? []
    return mine.enumerated().sorted { a, b in
      let na = needAfter(fen, a.element), nb = needAfter(fen, b.element)
      return na != nb ? na > nb : a.offset < b.offset
    }.map(\.element)
  }

  /// Everything playable here: your lines first, then the book by popularity.
  func moves(_ fen: String) -> [String] {
    let mine = prep[positionKey(fen)] ?? []
    let book = (lookup(index, fen)?.moves ?? []).jsSorted { cmp($1.games, $0.games) }.map(\.san)
    return mine + book.filter { !mine.contains($0) }
  }

  func weights(_ fen: String, _ played: [String]) -> [(san: String, weight: Double)] {
    var options = prep[positionKey(fen)] ?? []
    // A gap due a new move: its reply is played here, though no line of yours meets it yet.
    for line in due where line.count == played.count + 1 && Array(line.prefix(played.count)) == played {
      if !options.contains(line[played.count]) { options.append(line[played.count]) }
    }
    if options.isEmpty { return [] }
    // Your pick on Home: on the way in, the opponent heads for it where it can.
    if headed, lineStatus(tree, node, played) == .onWay {
      // Its own move order first, then any way the book still reaches it by.
      let own = played.count < node.sans.count && Array(node.sans.prefix(played.count)) == played
        ? options.filter { $0 == node.sans[played.count] } : []
      let toward = own.isEmpty ? options.filter { lineStatus(tree, node, played + [$0]) != .outside } : own
      if !toward.isEmpty { options = toward }
    }
    let entry = lookup(index, fen)
    var games: [String: Double] = [:]
    for move in entry?.moves ?? [] { games[move.san] = move.games }
    let shares = withFloor(options.map { games[$0] ?? 0 }, options.map { _ in true })
    return options.enumerated().map { i, san in
      let toGap = due.contains { line in line.count > played.count && Array(line.prefix(played.count + 1)) == played + [san] }
      return (san, shares[i] * needAfter(fen, san) * (toGap ? DUE_GAP_BOOST : 1))
    }
  }

  var source = LineSource(
    label: node.name, color: color, node: node,
    movesAt: { fen, _ in moves(fen) },
    weightsAt: { fen, played in weights(fen, played) },
    prepAt: { fen in prep[positionKey(fen)] ?? [] })
  source.rankedPrep = ranked
  source.offPrepFinal = true
  return source
}

/// The lines of the gaps on one side of a selection that are due a new move now.
public func dueGapLines(_ state: AppState, _ tree: OpeningTree, _ selection: Selection, color: Color) -> [[String]] {
  let reps = state.playbookList
  let p = pace(runs: runsSinceAdded(state.games, reps), size: state.settings.movesPerFill)
  if p < 1 { return [] }
  let ranked = selectionGaps(state, tree, selection)
  guard let top = ranked.first else { return [] }
  return ranked.filter { $0.color == color && insideYourLines($0) && growScore($0, top: top, pace: p, reps: reps, cards: state.cards) >= 1 }.map(\.line)
}
