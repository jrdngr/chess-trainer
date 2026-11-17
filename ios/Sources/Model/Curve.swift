import Book
import ChessCore
import Foundation
import Shared

/// The coverage curve: where the Playbook grows next. Depth first: the hole
/// you meet most often inside your lines grows next, one fill at a time. Replies
/// that leave your lines at the opponent's move 2, then move 1, open as levels,
/// each once there is nothing deeper to grow, you have played enough games and
/// every opening you have is green.

/// The least share of your games that must reach a hole for it to grow.
public let CURVE_MIN_REACH = 0.01
/// The games you must have played before a level opens.
public let CURVE_LEVEL_GAMES: [Int: Int] = [2: 20, 1: 40]
/// The form every opening you have needs before a level opens.
public let CURVE_GREEN = 0.8
/// How deep holes are looked for, in plies.
private let CURVE_MAX_PLY = 40

/// A hole's level: 1 or 2 when its reply is the opponent's first or second
/// move and you answer another reply there, so it leaves your openings; 0 for
/// every hole deeper in, and where a line just stops.
public func curveLevel(_ gap: Gap) -> Int {
  guard gap.kind == .noAnswer else { return 0 }
  let move = gap.hole.path.count / 2 + 1
  return move <= 2 ? move : 0
}

/// The sides the curve grows: Black only once the side picker is yours.
public func curveSides(_ state: AppState) -> [Playbook] {
  state.playbookList.filter { !$0.nodes.isEmpty && ($0.color == .w || state.owns(.sidePicker)) }
}

/// Every hole the curve could grow in some sides' Playbooks, whatever its level:
/// met in at least 1% of your games, still inside the opening the book names.
/// Most met first; ties go shallower, then White first, then by the line.
public func curveHoles(_ reps: [Playbook], _ index: ReferenceIndex, tree: OpeningTree? = nil, scope: OpeningNode? = nil) -> [Gap] {
  var out: [Gap] = []
  for rep in reps where !rep.nodes.isEmpty {
    let region = tree.flatMap { t in scope.flatMap { $0.depth > 0 ? (tree: t, node: $0) : nil } }
    let holes = findHoles(rep, index, GrowthOptions(minShare: DEFAULT_MIN_SHARE, maxPly: CURVE_MAX_PLY, region: region))
    // Where a line just stops, its most played reply is where it goes on; the others leave it.
    var stops: [String: String] = [:]
    for hole in holes where !hole.path.isEmpty {
      guard let id = hole.nodeId, !childrenOf(rep, id).contains(where: { !childrenOf(rep, $0.id).isEmpty }) else { continue }
      let best = stops[id].flatMap { san in holes.first { $0.nodeId == id && $0.san == san } }
      if best.map({ hole.share > $0.share }) ?? true { stops[id] = hole.san }
    }
    for hole in holes {
      let reach = hole.reach * hole.share / 100
      guard reach >= CURVE_MIN_REACH else { continue }
      let line = hole.path + [hole.san]
      guard let end = namedEnd(index, line), end.ply >= line.count else { continue }
      out.append(Gap(
        kind: hole.nodeId.flatMap { stops[$0] } == hole.san ? .tooShort : .noAnswer, playbookId: rep.id, color: rep.color, hole: hole,
        importance: reach, name: deepestName(index, line)?.name ?? end.name, missing: max(1, (end.ply - line.count + 1) / 2)))
    }
  }
  return rankGaps(out)
}

/// What the levels wait for besides the holes: the games you have played, and
/// how many of the openings you have are green.
public struct CurveGate: Equatable, Sendable {
  public var games: Int
  public var green: Int
  public var openings: Int
  public init(games: Int, green: Int, openings: Int) {
    self.games = games
    self.green = green
    self.openings = openings
  }
  /// Every opening you have is green.
  public var allGreen: Bool { green >= openings }
  /// Whether a level's game count and form are met.
  public func met(_ level: Int) -> Bool { allGreen && games >= (CURVE_LEVEL_GAMES[level] ?? 0) }
}

/// The openings you have on some sides: the deepest named opening each of your lines reaches.
public func ownedOpenings(_ reps: [Playbook], _ tree: OpeningTree) -> [OpeningNode] {
  var seen = Set<String>()
  var out: [OpeningNode] = []
  for rep in reps {
    for line in leafLines(rep) {
      guard let node = deepestNodeAlong(tree, line.sans), node.depth >= 2, seen.insert(node.id).inserted else { continue }
      out.append(node)
    }
  }
  return out
}

/// An opening's form, the average of its last answers; nil before it has enough.
public func formAverage(_ form: FormRecord, _ id: String) -> Double? {
  let scores = form.openings[id] ?? []
  guard scores.count >= FORM_MIN_ANSWERS else { return nil }
  return scores.reduce(0, +) / Double(scores.count)
}

/// Whether an opening is green: enough answers, averaging at least `CURVE_GREEN`.
public func isGreen(_ form: FormRecord, _ id: String) -> Bool { (formAverage(form, id) ?? 0) >= CURVE_GREEN }

/// The Play games you have played.
public func playGames(_ state: AppState) -> Int { state.games.filter { $0.mode == .play }.count }

public func curveGate(_ state: AppState, _ tree: OpeningTree) -> CurveGate {
  let owned = ownedOpenings(curveSides(state), tree)
  return CurveGate(games: playGames(state), green: owned.filter { isGreen(state.form, $0.id) }.count, openings: owned.count)
}

/// The levels open now. Depth is always open. Level 2 opens once no hole is left
/// in the open levels and its gate is met; level 1 the same after level 2.
public func openLevels(_ holes: [Gap], _ gate: CurveGate) -> Set<Int> {
  var open: Set<Int> = [0]
  for level in [2, 1] {
    if holes.contains(where: { open.contains(curveLevel($0)) }) || !gate.met(level) { break }
    open.insert(level)
  }
  return open
}

/// The holes the curve may grow now in the whole Playbook, most met first.
public func curvePlaybookGaps(_ state: AppState, _ tree: OpeningTree) -> [Gap] {
  let holes = curveHoles(curveSides(state), tree.index, tree: tree)
  let open = openLevels(holes, curveGate(state, tree))
  return holes.filter { open.contains(curveLevel($0)) }
}

/// The holes the curve may grow now inside a selection. Levels open by the whole Playbook.
public func curveSelectionGaps(_ state: AppState, _ tree: OpeningTree, _ selection: Selection) -> [Gap] {
  let sides = curveSides(state)
  let open = openLevels(curveHoles(sides, tree.index, tree: tree), curveGate(state, tree))
  var out: [Gap] = []
  for region in regionsBySide(tree, selection) {
    out += curveHoles(sides.filter { $0.color == region.side }, tree.index, tree: tree, scope: region.node)
  }
  var seen = Set<String>()
  return rankGaps(out.filter { open.contains(curveLevel($0)) && seen.insert($0.id).inserted })
}

/// Play runs until the next growth is due, 0 when it is due now.
public func runsUntilGrowth(_ state: AppState) -> Int {
  max(0, state.settings.movesPerFill - runsSinceAdded(state.games, state.playbookList))
}


/* ── Black's answers ── */

/// How sharp the opening a line reaches is, 1 to 5; 3 when the picker doesn't know it.
public func sharpnessOf(_ tree: OpeningTree, _ line: [String]) -> Sharpness {
  guard let node = deepestNodeAlong(tree, line) else { return 3 }
  return entryForNode(pickerCatalog(tree), node)?.sharpness ?? 3
}

/// Answers as Black: the calmest of the three most played goes first, the rest
/// keep their order. As White the order stays.
public func calmFirst<T>(_ tree: OpeningTree, _ path: [String], color: Color, _ answers: [T], san: (T) -> String) -> [T] {
  guard color == .b, answers.count > 1 else { return answers }
  let top = Array(answers.prefix(3))
  let calmest = top.indices.min { a, b in
    let sa = sharpnessOf(tree, path + [san(top[a])]), sb = sharpnessOf(tree, path + [san(top[b])])
    return sa != sb ? sa < sb : a < b
  }!
  var out = answers
  out.insert(out.remove(at: calmest), at: 0)
  return out
}

/* ── unlocking early ── */

/// The moves an early unlock adds at a hole: the reply, then your answer and the
/// most played reply in turn, for one fill of your moves, ending with the named
/// opening or where no reply is common enough.
public func unlockLine(_ tree: OpeningTree, _ gap: Gap, size: Int) -> [String] {
  let index = tree.index
  var line = gap.line
  var added = 0
  while true {
    let walked = walkSan(line)
    guard walked.moves.count == line.count else { break }
    let fen = walked.fens[line.count]
    if fenTurn(fen) == gap.color {
      let answers = calmFirst(tree, line, color: gap.color, popularReplies(index, fen, 0).prefix(3).map(\.san), san: { $0 })
      guard let pick = answers.first else { break }
      line.append(pick)
      added += 1
      if fillEnds(index, line, added: added, size: size) { break }
    } else {
      guard let reply = popularReplies(index, fen, GAP_SHARE).first else { break }
      line.append(reply.san)
    }
  }
  return line
}

extension AppState {
  /// Grow a hole now, free: the line `unlockLine` gives goes into its side's
  /// Playbook. Returns whether anything was added.
  @discardableResult
  public mutating func unlockEarly(_ gap: Gap, _ tree: OpeningTree) -> Bool {
    guard let rep = playbookList.first(where: { $0.color == gap.color }) else { return false }
    let line = unlockLine(tree, gap, size: settings.movesPerFill)
    guard line.count > gap.line.count else { return false }
    addLine(rep.id, line, .fixed(.growth), via: .growth)
    logEvent(AppEvent(kind: "unlock", color: gap.color, line: line.joined(separator: " ")))
    return true
  }
}
