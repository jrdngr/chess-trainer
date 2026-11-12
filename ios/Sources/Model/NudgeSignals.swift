import Book
import ChessCore
import Shared

/// The signals the nudges are coloured by.

struct Signals {
  var san: String
  /// Lands on one of your positions: 1, or the share of replies that take it there.
  var transposes: Double
  var transposesInto: [String]?
  var transposesNow: Bool
  /// The share of replies after which one more move of yours lands on one of your positions.
  var heads: Double
  var headsInto: [String]?
  /// Times you choose this move elsewhere in the opening and its kin, and the families, most first.
  var habit: Int
  var habitFrom: [String]
  /// Positions in the opening whose pawns of yours this move reaches.
  var pawns: Int
  /// Lines in the opening this move makes unreachable.
  var closes: Int
  var closesFrom: [String]
  /// Times it was a book option in the opening and you chose otherwise.
  var passed: Int
  var passedFrom: [String]
  /// The setup this move belongs to that you use most near here, if any.
  var setup: Setup?
  var setupUses: Int
  var setupFrom: [String]
  var setupPassed: Int
}

/// What asking about a move leaves out: positions behind you, or going with a subtree.
public struct SignalOptions {
  /// Positions to treat as gone, as if their lines were not in the playbook.
  public var gone: Set<String>?
  /// Count the lines each move closes off (red), which costs the most. Default true.
  public var away: Bool?
  /// The positions along the line, root first, when the caller already has them.
  public var pathKeys: [String]?
  public init(gone: Set<String>? = nil, away: Bool? = nil, pathKeys: [String]? = nil) {
    self.gone = gone
    self.away = away
    self.pathKeys = pathKeys
  }
}

/// The positions along a line.
func pathKeys(_ path: [String], _ rootFen: String) -> [String] {
  walkSan(path, rootFen).fens.map(positionKey)
}

/// Your moves on a line from the start, as `sameMove` writes them.
func yourMovesAlong(_ path: [String], _ color: Color) -> Set<String> {
  let first = color == .w ? 0 : 1
  return Set(path.enumerated().filter { $0.offset % 2 == first }.map { sameMove($0.element) })
}

private func keyAfter(_ fen: String, _ san: String) -> String? {
  applySan(fen, san).map { positionKey($0.after) }
}

/// Everything the arrows are coloured by, for one position and the moves asked about there.
func signalsFor(
  _ profile: NudgeProfile, _ index: ReferenceIndex, _ path: [String], _ fen: String, _ sans: [String],
  _ prefs: NudgePrefs, _ minShare: Double, _ opts: SignalOptions = SignalOptions()
) -> (signals: [Signals], family: String?) {
  let keys = opts.pathKeys ?? pathKeys(path, profile.rootFen)
  let fam = familyAlong(index, keys)
  let context = contextOf(profile, index, fam, minShare)
  func familyOf(_ node: ProfileNode) -> String { node.family ?? fam ?? "" }

  // The line so far: a move back into it is not a transposition, a line that
  // ends on it is behind you, and a choice made on it is not a habit.
  var removed = Set(keys)
  removed.insert(positionKey(fen))
  removed.formUnion(opts.gone ?? [])

  let away = opts.away ?? true
  let openBefore = away
    ? context.leaves.filter { $0.depth > path.count && !removed.contains($0.after) && reachable(fen, $0.fenAfter) }
    : []
  // Lines another move you keep here still reaches are not closed off by this one.
  let here = positionKey(fen)
  let kept = away
    ? uniqueBy(profile.nodes.filter { $0.mine && $0.before == here && !removed.contains($0.after) }, \.san)
    : []
  var keptReach: [String: [String]] = [:]
  for leaf in openBefore {
    keptReach[leaf.after] = kept.filter { reachable($0.fenAfter, leaf.fenAfter) }.map { sameMove($0.san) }
  }
  let myPawnsNow = pawnsOf(fen, profile.color)
  var usualPawns: [String: Int] = [:]
  if prefs.pawns {
    for node in uniqueBy(context.scope, \.after) where !removed.contains(node.after) {
      usualPawns[pawnsOf(node.fenAfter, profile.color), default: 0] += 1
    }
  }
  /// One of your positions, off the line so far.
  func yours(_ key: String) -> [String]? { removed.contains(key) ? nil : profile.positions[key] }

  let mineAlong = yourMovesAlong(path, profile.color)
  var signals: [Signals] = []
  for san in sans {
    guard let move = applySan(fen, san) else { continue }
    let key = positionKey(move.after)
    var transposes = 0.0
    var transposesInto: [String]?
    var transposesNow = false
    var heads = 0.0
    var headsInto: [String]?
    if let line = yours(key) {
      transposes = 1
      transposesInto = line
      transposesNow = true
    } else {
      // Their reply, and then one move of yours, both read off the book's links.
      let entry = index.entries[key]
      let total = entry?.moves.reduce(0) { $0 + $1.games } ?? 0
      for reply in entry?.moves ?? [] {
        let share = total != 0 ? reply.games / total : 0
        if share * 100 < minShare { continue }
        guard let replyKey = reply.next ?? keyAfter(move.after, reply.san) else { continue }
        if let line = yours(replyKey) {
          transposes += share
          if transposesInto == nil { transposesInto = line }
          continue
        }
        for next in index.entries[replyKey]?.moves ?? [] {
          guard let later = next.next.flatMap(yours) else { continue }
          heads += share
          if headsInto == nil { headsInto = later }
          break
        }
      }
      if transposes < VIA_REPLY_MIN {
        transposes = 0
        transposesInto = nil
      }
      if heads < VIA_REPLY_MIN {
        heads = 0
        headsInto = nil
      }
    }
    let same = sameMove(san)
    let myPawns = pawnsOf(move.after, profile.color)
    var closedFrom = OrderedMap<String, Int>()
    var closes = 0
    // Castling shuts nothing a line of yours is heading for: it is how those lines carry on.
    let castles = same.hasPrefix("O-O")
    for leaf in castles ? [] : openBefore {
      if reachable(move.after, leaf.fenAfter) { continue }
      if keptReach[leaf.after]?.contains(where: { $0 != same }) == true { continue }
      closes += 1
      closedFrom[familyOf(leaf)] = (closedFrom[familyOf(leaf)] ?? 0) + 1
    }
    let habitCounts = near(context.habits[same], path.count, removed)
    let passedCounts = near(context.passedOn[same], path.count, removed)
    var setup: Setup?
    var setupCounts: OrderedMap<String, Int>?
    var setupPassed = 0
    for candidate in setupsWith(profile.color, same) {
      if !signsSetup(candidate, mineAlong, same) { continue }
      let uses = near(context.setupUses[candidate.id], path.count, removed, SETUP_PLIES)
      if setup != nil && sum(uses) <= sum(setupCounts) { continue }
      setup = candidate
      setupCounts = uses
      setupPassed = sum(near(context.setupPasses[candidate.id], path.count, removed, SETUP_PLIES))
    }
    signals.append(Signals(
      san: san, transposes: transposes, transposesInto: transposesInto, transposesNow: transposesNow,
      heads: heads, headsInto: headsInto, habit: sum(habitCounts), habitFrom: ranked(habitCounts),
      pawns: prefs.pawns && myPawns != myPawnsNow ? usualPawns[myPawns] ?? 0 : 0,
      closes: closes, closesFrom: ranked(closedFrom), passed: sum(passedCounts), passedFrom: ranked(passedCounts),
      setup: setup != nil && sum(setupCounts) > 0 ? setup : nil, setupUses: sum(setupCounts),
      setupFrom: ranked(setupCounts), setupPassed: setupPassed))
  }
  return (signals, fam)
}
