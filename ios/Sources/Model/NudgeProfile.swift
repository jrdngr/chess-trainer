import Book
import ChessCore
import Shared

/// Nudges: keeping a repertoire narrow while it grows. Four files: the profile and context here, the signals, the arrows, and
/// the switches Tidy offers.
///
/// A move that lands in a position you already know, or one you already play
/// in the same opening, costs almost nothing to learn; one that shuts off the
/// lines you have costs a new line of its own. So the arrows are coloured:
/// green (or yellow, pulled in) for the familiar move, red for the move that
/// closes off your lines or that you keep passing on.

public struct NudgePrefs: Equatable, Sendable {
  public var priority: NudgePriority
  /// Count reaching your usual pawns as a (weaker) habit.
  public var pawns: Bool
  public init(priority: NudgePriority, pawns: Bool) {
    self.priority = priority
    self.pawns = pawns
  }
}

/// A move you have played this often in the opening is a habit.
public let HABIT_MIN = 2
/// The share of games, 0...1, that have to reach one of your positions after
/// their reply for a move to count as transposing on the way.
public let VIA_REPLY_MIN = 0.25
/// How far apart, in plies, a choice can be and still count as the same habit.
public let HABIT_PLIES = 4
/// A setup is one plan whenever it comes in, so it is looked for twice as far.
let SETUP_PLIES = 8
/// How far down a line a move can come and still only be put off: your next two moves.
private let DELAY_PLIES = 5

/* ── the profile ── */

struct ProfileNode {
  var id: String
  /// Positions before and after, as position keys.
  var before: String
  var after: String
  var fenAfter: String
  var san: String
  /// Whether the move is yours.
  var mine: Bool
  /// The opening the line is filed under, or nil before the book names one.
  var family: String?
  var depth: Int
  var leaf: Bool
}

/// A repertoire from the point of view of a move being added: every move in
/// it, the opening each belongs to, and every position it reaches.
struct Profile {
  var color: Color
  var rootFen: String
  var nodes: [ProfileNode]
  /// Every position in the repertoire, with the line that reaches it first.
  var positions: [String: [String]]
}

func profileOf(_ rep: Repertoire, _ index: ReferenceIndex) -> Profile {
  var nodes: [ProfileNode] = []
  var positions: [String: [String]] = [positionKey(rep.rootFen): []]
  // The deepest name so far is carried down rather than looked up per line.
  func walk(_ nodeId: String?, _ path: [String], _ named: String?) {
    for kid in childrenOf(rep, nodeId) {
      let line = path + [kid.san]
      let after = positionKey(kid.fenAfter)
      let name = index.names[after]?.name ?? named
      if positions[after] == nil { positions[after] = line }
      nodes.append(ProfileNode(
        id: kid.id, before: kid.key, after: after, fenAfter: kid.fenAfter, san: kid.san,
        mine: fenTurn(kid.fenBefore) == rep.color, family: name.map { familyName(index, $0) },
        depth: line.count, leaf: kid.children.isEmpty))
      walk(kid.id, line, name)
    }
  }
  walk(nil, [], nil)
  return Profile(color: rep.color, rootFen: rep.rootFen, nodes: nodes, positions: positions)
}

/// `openingOf`, for a line already given as its positions.
func familyAlong(_ index: ReferenceIndex, _ keys: [String]) -> String? {
  for i in stride(from: keys.count - 1, through: 1, by: -1) {
    if let named = index.names[keys[i]] { return familyName(index, named.name) }
  }
  return nil
}

/// Check and capture marks do not make a different habit: Nxe5 is Ne5.
public func sameMove(_ san: String) -> String {
  var out = san.filter { !"+#!?".contains($0) }
  if let x = out.firstIndex(of: "x") { out.remove(at: x) }
  return out
}

/* ── the context ── */

/// One place you chose, or passed on, a move.
struct SeenAt {
  var key: String
  var ply: Int
  var family: String
}

/// What one opening (with its kin) looks like, counted once: the places you
/// chose and what, the book moves you passed on there, and the lines that end
/// in it.
struct NudgeContext {
  var scope: [ProfileNode]
  var habits: [String: [SeenAt]] = [:]
  var passedOn: [String: [SeenAt]] = [:]
  /// How many times each move was chosen, and passed on, at each ply.
  var byPly: [Int: OrderedMap<String, Int>] = [:]
  var passedByPly: [Int: OrderedMap<String, Int>] = [:]
  /// Where each line takes a setup up, and where it was offered and never taken. Keyed by setup id.
  var setupUses: [String: [SeenAt]] = [:]
  var setupPasses: [String: [SeenAt]] = [:]
  var leaves: [ProfileNode] = []
}

/// The book's moves at a position above a share.
func bookMovesAt(_ index: ReferenceIndex, _ fen: String, _ minShare: Double) -> [String] {
  popularReplies(index, fen, minShare).map(\.san)
}

private struct Chosen {
  var moves: [String]
  var family: String
  var ply: Int
}

func contextOf(_ profile: Profile, _ index: ReferenceIndex, _ fam: String?, _ minShare: Double) -> NudgeContext {
  // The opening and its kin: a new Catalan already knows your English's g3.
  let kin = fam.map(kinOf)
  var context = NudgeContext(scope: profile.nodes.filter { kin == nil || ($0.family != nil && kin!.contains($0.family!)) })
  var fenBefore: [String: String] = [positionKey(profile.rootFen): profile.rootFen]
  for node in profile.nodes where fenBefore[node.after] == nil { fenBefore[node.after] = node.fenAfter }
  // Where you have already chosen, and what: one entry per position.
  var chosen = OrderedMap<String, Chosen>()
  for node in context.scope where node.mine {
    var at = chosen[node.before] ?? Chosen(moves: [], family: node.family ?? fam ?? "", ply: node.depth - 1)
    let move = sameMove(node.san)
    if !at.moves.contains(move) { at.moves.append(move) }
    chosen[node.before] = at
  }
  // Your moves a little further down each line: a move you play a turn or two later was put off, not passed on.
  var from: [String: [ProfileNode]] = [:]
  for node in profile.nodes { from[node.before, default: []].append(node) }
  func soonAfter(_ key: String) -> Set<String> {
    var out = Set<String>()
    var frontier = [key]
    var ply = 0
    while ply < DELAY_PLIES && !frontier.isEmpty {
      var next: [String] = []
      for at in frontier {
        for node in from[at] ?? [] {
          if ply > 0 && node.mine { out.insert(sameMove(node.san)) }
          next.append(node.after)
        }
      }
      frontier = next
      ply += 1
    }
    return out
  }
  for (key, at) in chosen.entries {
    let seen = SeenAt(key: key, ply: at.ply, family: at.family)
    var counts = context.byPly[at.ply] ?? OrderedMap()
    for move in at.moves {
      context.habits[move, default: []].append(seen)
      counts[move] = (counts[move] ?? 0) + 1
    }
    context.byPly[at.ply] = counts
    // What else the book offered there, for "you keep passing on it".
    guard let fen = fenBefore[key] else { continue }
    var passed = context.passedByPly[at.ply] ?? OrderedMap()
    let later = soonAfter(key)
    for san in bookMovesAt(index, fen, minShare) {
      let move = sameMove(san)
      if at.moves.contains(move) || later.contains(move) { continue }
      context.passedOn[move, default: []].append(seen)
      passed[move] = (passed[move] ?? 0) + 1
    }
    context.passedByPly[at.ply] = passed
  }
  // Setups: your moves along each position's line, read up the tree once.
  var into: [String: ProfileNode] = [:]
  for node in profile.nodes where into[node.after] == nil { into[node.after] = node }
  var lineMoves: [String: Set<String>] = [:]
  func movesBefore(_ key: String) -> Set<String> {
    if let known = lineMoves[key] { return known }
    let node = into[key]
    var out = node.map { movesBefore($0.before) } ?? []
    if let node, node.mine { out.insert(sameMove(node.san)) }
    lineMoves[key] = out
    return out
  }
  let setups = setupsFor(profile.color)
  for (key, at) in chosen.entries {
    let seen = SeenAt(key: key, ply: at.ply, family: at.family)
    let before = movesBefore(key)
    let offered = fenBefore[key].map { bookMovesAt(index, $0, minShare).map(sameMove) } ?? []
    let later = soonAfter(key)
    for setup in setups {
      if usesSetup(setup, before) { continue }
      if at.moves.contains(where: { move in setup.core.allSatisfy { $0 == move || before.contains($0) } }) {
        context.setupUses[setup.id, default: []].append(seen)
      } else if offered.contains(where: { signsSetup(setup, before, $0) }),
        !(at.moves + later).contains(where: { setup.moves.contains($0) }) {
        context.setupPasses[setup.id, default: []].append(seen)
      }
    }
  }
  context.leaves = uniqueBy(context.scope.filter(\.leaf), \.after)
  return context
}

/// The entries near a depth, off the removed positions, by family.
func near(_ list: [SeenAt]?, _ ply: Int, _ removed: Set<String>, _ window: Int = HABIT_PLIES) -> OrderedMap<String, Int> {
  var out = OrderedMap<String, Int>()
  for seen in list ?? [] where abs(seen.ply - ply) <= window && !removed.contains(seen.key) {
    out[seen.family] = (out[seen.family] ?? 0) + 1
  }
  return out
}

/// The families a tally came from, most first.
func ranked(_ counts: OrderedMap<String, Int>?) -> [String] {
  (counts?.entries ?? []).filter { $0.value > 0 }.jsSorted { cmp($1.value, $0.value) }.map(\.key)
}

func sum(_ counts: OrderedMap<String, Int>?) -> Int {
  counts?.values.reduce(0, +) ?? 0
}

func uniqueBy<T>(_ items: [T], _ key: (T) -> String) -> [T] {
  var seen = Set<String>()
  return items.filter { seen.insert(key($0)).inserted }
}
