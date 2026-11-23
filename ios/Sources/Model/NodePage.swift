import Book
import ChessCore

/// The page an opening of yours on the tree opens: that one position, how
/// well you know it, and what growing under it waits for. View lines walks your Playbook on past it.

/// What growing under an opening waits for.
public enum NodeGrow: Equatable, Sendable {
  /// A hole under it is in an open level: Grow fills it.
  case ready(Gap)
  /// Its first hole waits for its level, which opens at `gamesNeeded` games
  /// once every opening you have is green.
  case level(Int, games: Int, gamesNeeded: Int, green: Int, openings: Int)
  /// Its holes wait until the curve has grown `count` holes elsewhere, `next` first.
  case after(next: Gap, count: Int)
  /// Nothing under it for the curve to grow.
  case none
}

public struct NodePage: Equatable, Sendable {
  /// The opening's last answers to your move on this side, oldest first.
  public var answers: [Double]
  /// Their average, 0 to 1; nil before there are enough of them.
  public var form: Double?
  public var grow: NodeGrow
}

/// The page for the opening `id`, reached by `line`, on `side`'s tree.
public func nodePage(_ state: AppState, _ tree: OpeningTree, side: Color, id: String, line: [String]) -> NodePage {
  let key = tree.byId[id]?.key ?? positionKey(walkSan(line).fens.last ?? START_FEN)
  let answers = FormAtMove(state.events).scores(key, side)
  let all = curveHoles(curveSides(state), tree.index, tree: tree)
  let under = all.filter { $0.color == side && $0.line.count > line.count && $0.line.starts(with: line) }
  return NodePage(answers: answers, form: formOf(answers), grow: nodeGrow(under, all, curveGate(state, tree)))
}

/// The first hole under the opening the open levels allow; else what opens them:
/// holes in open levels elsewhere grow first, then its first hole's level opens.
public func nodeGrow(_ under: [Gap], _ all: [Gap], _ gate: CurveGate) -> NodeGrow {
  guard !under.isEmpty else { return .none }
  let open = openLevels(all, gate)
  if let gap = under.first(where: { open.contains(curveLevel($0)) }) { return .ready(gap) }
  let ahead = all.filter { open.contains(curveLevel($0)) }
  if let next = ahead.first { return .after(next: next, count: ahead.count) }
  let level = curveLevel(under[0])
  return .level(
    level, games: gate.games, gamesNeeded: CURVE_LEVEL_GAMES[level] ?? 0, green: gate.green, openings: gate.openings)
}

/// Moves View lines shows dimmed after each of your next moves.
public let VIEW_LINES_AHEAD = 3

extension AppState {
  /// Your Playbook's moves from where `line` leads on `side`, in its order: what View lines lists.
  /// Empty when the line isn't yours or ends there.
  public func nextMoves(_ side: Color, _ line: [String]) -> [String] {
    guard let rep = playbookList.first(where: { $0.color == side }) else { return [] }
    if line.isEmpty { return childrenOf(rep, nil).map(\.san) }
    guard let at = nodeAtLine(rep, line) else { return [] }
    return childrenOf(rep, at.id).map(\.san)
  }

  /// How your Playbook goes on after `line`, up to `count` moves: your preferred move on your
  /// turn, the first reply in your Playbook on theirs. View lines shows it dimmed after each move.
  public func lineAfter(_ side: Color, _ line: [String], count: Int = VIEW_LINES_AHEAD) -> [String] {
    guard let rep = playbookList.first(where: { $0.color == side }), var at = nodeAtLine(rep, line) else { return [] }
    var out: [String] = []
    while out.count < count {
      let kids = childrenOf(rep, at.id)
      let mine = fenTurn(at.fenAfter) == side
      guard let next = mine ? (kids.first(where: \.preferred) ?? kids.first) : kids.first else { break }
      out.append(next.san)
      at = next
    }
    return out
  }

  /// The moves Delete takes from an opening's page: its last move and everything after it.
  public func movesUnder(_ side: Color, _ line: [String]) -> Int {
    guard let rep = playbookList.first(where: { $0.color == side }), let at = nodeAtLine(rep, line) else { return 0 }
    return subtreeIds(rep, at.id).count
  }

  /// Delete from an opening's page, or from View lines on it: the line's last move and everything
  /// after it, with an undo. Nothing at or before the named position of an opening you have.
  @discardableResult
  public mutating func removeNodeAt(_ side: Color, _ line: [String]) -> PlaybookUndo? {
    guard canDelete(side, line), let rep = playbookList.first(where: { $0.color == side }), let at = nodeAtLine(rep, line) else { return nil }
    return removeNode(rep.id, at.id)
  }
}
