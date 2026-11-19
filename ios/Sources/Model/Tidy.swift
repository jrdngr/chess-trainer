import Book
import ChessCore
import Shared

/// Tidy: finding the places a playbook could converge.
///
/// At each move you chose, the book's other moves are compared with yours by
/// how they reach the rest of your lines: one that lands on a position you
/// already have (transposes), or gets there after a common reply and one more
/// move of yours (heads toward). Your own move is judged against the playbook
/// *without* its subtree, so it gets no credit for being the line it already
/// is. A move you play in similar positions elsewhere is no reason to switch.
///
/// Of the moves that reach your lines, the engine's best is offered, and never
/// one clearly worse than yours. A find shows two lines from where they split:
/// yours, and the one the switch leads into, played on into your Playbook.

/// What makes a move a switch: these kinds only, transpositions first.
let TIDY_KINDS: [TowardKind] = [.transposes, .heads]

/// Moves of your Playbook the target line plays on after it reaches it.
public let TIDY_KNOWN_STEPS = 3

/// A position where another move would bring your lines together, before
/// the engine has picked among the moves that would.
public struct TidyChoice: Equatable, Sendable {
  public var playbookId: String
  public var color: Color
  /// Your move at the position.
  public var nodeId: String
  public var mine: String
  /// The line to the position, and the position itself.
  public var path: [String]
  public var fen: String
  /// The moves that reach your lines where yours does not, best kind first.
  public var options: [TidyOption]
  /// Moves the switch removes: your move and everything under it.
  public var removes: Int
}

public struct TidyOption: Equatable, Sendable {
  public var san: String
  public var kind: TowardKind
  public var strength: Double
  /// The line of yours it reaches.
  public var into: [String]
  public init(san: String, kind: TowardKind, strength: Double, into: [String]) {
    self.san = san
    self.kind = kind
    self.strength = strength
    self.into = into
  }
}

public struct TidyFind: Equatable, Sendable {
  /// Stable while the line is unchanged: the playbook and your move's node.
  public var id: String
  public var playbookId: String
  public var color: Color
  public var nodeId: String
  public var mine: String
  public var path: [String]
  public var fen: String
  /// The move to switch to, and how it reaches your lines.
  public var suggestion: String
  public var kind: TowardKind
  public var removes: Int
  /// The current line from the split: your move, then your Playbook's main way on.
  public var current: [String]
  /// The target line from the split: the switch, the moves to a position you
  /// have, then up to `TIDY_KNOWN_STEPS` of your moves and replies from there.
  public var target: [String]
  /// How many of the target's moves it takes to reach your Playbook.
  public var joins: Int
}

public struct TidyOptions: Sendable {
  public var minShare: Double
  public init(minShare: Double) { self.minShare = minShare }
}

/// Centipawns a move gives up against the best move, for the side to move; nil until known.
public typealias MoveLoss = (_ fen: String, _ san: String) -> Double?

/// The moves that would tidy a position, or nil when none reaches your lines better than yours.
public func choiceAt(_ rep: Playbook, _ index: ReferenceIndex, _ node: RepMove, _ opts: TidyOptions) -> TidyChoice? {
  let line = pathTo(rep, node.parentId)
  let path = line.map(\.san)
  // Your first move picks the opening: two first moves are two openings, not a loose end.
  if isFirstMove(path) { return nil }
  let profile = profileOf(rep, index)
  if profile.nodes.isEmpty { return nil }
  let fen = node.fenBefore
  let siblings = Set(childrenOf(rep, node.parentId).map(\.san))
  let others = popularReplies(index, fen, opts.minShare).map(\.san).filter { !siblings.contains($0) }
  if others.isEmpty { return nil }
  let keys = [positionKey(rep.rootFen)] + line.map { positionKey($0.fenAfter) }
  let signalOpts = SignalOptions(gone: goneWith(rep, index, node.id), away: false, pathKeys: keys)
  let (signals, _) = signalsFor(profile, index, path, fen, [node.san] + others, NudgePrefs(priority: .transposition, pawns: false), opts.minShare, signalOpts)
  func reach(_ s: Signals) -> (rank: Int, strength: Double, into: [String])? {
    if s.transposes > 0, let into = s.transposesInto { return (0, s.transposes, into) }
    if s.heads > 0, let into = s.headsInto { return (1, s.heads, into) }
    return nil
  }
  let bar = signals.first { $0.san == node.san }.flatMap(reach)
  var options: [TidyOption] = []
  for signal in signals where signal.san != node.san {
    guard let r = reach(signal) else { continue }
    if let bar, !(r.rank < bar.rank || (r.rank == bar.rank && r.strength > bar.strength)) { continue }
    options.append(TidyOption(san: signal.san, kind: TIDY_KINDS[r.rank], strength: r.strength, into: r.into))
  }
  if options.isEmpty { return nil }
  options = options.enumerated().sorted { a, b in
    let ka = TIDY_KINDS.firstIndex(of: a.element.kind)!, kb = TIDY_KINDS.firstIndex(of: b.element.kind)!
    if ka != kb { return ka < kb }
    if a.element.strength != b.element.strength { return a.element.strength > b.element.strength }
    return a.offset < b.offset
  }.map(\.element)
  return TidyChoice(
    playbookId: rep.id, color: rep.color, nodeId: node.id, mine: node.san, path: path, fen: fen,
    options: options, removes: subtreeIds(rep, node.id).count)
}

/// The moves whose loss a choice needs before it can be decided.
public func movesToJudge(_ choice: TidyChoice) -> [String] { [choice.mine] + choice.options.map(\.san) }

/// How a choice comes out once the engine has a say.
public enum TidyDecision: Equatable, Sendable {
  /// A loss is not known yet.
  case waiting
  /// Every move that would tidy it is clearly worse than yours.
  case none
  case find(TidyFind)
}

/// The engine picks: the option that gives up least, never one giving up more
/// than `CLEARLY_WORSE_CP` beyond yours. Ties go to the better kind.
public func decide(_ rep: Playbook, _ index: ReferenceIndex, _ choice: TidyChoice, _ loss: MoveLoss) -> TidyDecision {
  guard let mine = loss(choice.fen, choice.mine) else { return .waiting }
  var best: (option: TidyOption, loss: Double)?
  for option in choice.options {
    guard let l = loss(choice.fen, option.san) else { return .waiting }
    if l > mine + CLEARLY_WORSE_CP { continue }
    if best == nil || l < best!.loss { best = (option, l) }
  }
  guard let best, let node = rep.nodes[choice.nodeId] else { return .none }
  let target = targetLine(rep, index, choice.fen, best.option)
  return .find(TidyFind(
    id: "\(choice.playbookId)#\(choice.nodeId)", playbookId: choice.playbookId, color: choice.color, nodeId: choice.nodeId,
    mine: choice.mine, path: choice.path, fen: choice.fen, suggestion: best.option.san, kind: best.option.kind,
    removes: choice.removes, current: currentLine(rep, index, node, target.moves.count), target: target.moves, joins: target.joins))
}

/// What a card's two boards show after `step` moves of its stepper.
public struct TidyFrame: Equatable, Sendable {
  public var currentFen: String
  /// The current line's last move shown, nil before the first or once it has ended.
  public var currentMove: LegalMove?
  public var targetFen: String
  public var targetMove: LegalMove?
  /// The target line has reached a position you have: its later moves are ones you know.
  public var known: Bool
}

/// The card's boards at a step, from 0 (the split) to `target.count`. The current
/// line stops where it ends.
public func tidyFrame(_ find: TidyFind, _ step: Int) -> TidyFrame {
  let current = walkSan(find.current, find.fen), target = walkSan(find.target, find.fen)
  let c = min(max(0, step), current.moves.count), t = min(max(0, step), target.moves.count)
  return TidyFrame(
    currentFen: current.fens[c], currentMove: c > 0 && c == step ? current.moves[c - 1] : nil,
    targetFen: target.fens[t], targetMove: t > 0 ? target.moves[t - 1] : nil, known: t >= find.joins)
}

/// The reply most played in the book among `kids`, or the first when the book has none of them.
private func mainReply(_ index: ReferenceIndex, _ fen: String, _ kids: [RepMove]) -> RepMove? {
  let games = Dictionary(index.entries[positionKey(fen)]?.moves.map { ($0.san, $0.games) } ?? [], uniquingKeysWith: { a, _ in a })
  return kids.enumerated().max { a, b in
    let ga = games[a.element.san] ?? 0, gb = games[b.element.san] ?? 0
    return ga != gb ? ga < gb : a.offset > b.offset
  }?.element
}

/// Your Playbook's main way on from a node: your preferred move, the book's most played reply.
private func mainWay(_ rep: Playbook, _ index: ReferenceIndex, from nodeId: String?, _ count: Int) -> [String] {
  var out: [String] = []
  var at = nodeId
  while out.count < count {
    let kids = childrenOf(rep, at)
    let fen = fenAt(rep, at)
    let next = fenTurn(fen) == rep.color ? (kids.first(where: \.preferred) ?? kids.first) : mainReply(index, fen, kids)
    guard let next else { break }
    out.append(next.san)
    at = next.id
  }
  return out
}

/// The current line: your move, then as many moves as the target line shows, or fewer if it ends.
func currentLine(_ rep: Playbook, _ index: ReferenceIndex, _ node: RepMove, _ count: Int) -> [String] {
  [node.san] + mainWay(rep, index, from: node.id, max(0, count - 1))
}

/// The target line: the switch, the book's moves to a position you have, then your Playbook from there.
func targetLine(_ rep: Playbook, _ index: ReferenceIndex, _ fen: String, _ option: TidyOption) -> (moves: [String], joins: Int) {
  guard let landing = nodeAtLine(rep, option.into), let after = applySan(fen, option.san) else { return ([option.san], 1) }
  let goal = positionKey(landing.fenAfter)
  var bridge: [String] = [option.san]
  if positionKey(after.after) != goal { bridge += bookBridge(goal, from: after.after, index) ?? [] }
  return (bridge + mainWay(rep, index, from: landing.id, TIDY_KNOWN_STEPS), bridge.count)
}

/// The book's moves from `fen` to the position `goal`, two at most, most played first.
private func bookBridge(_ goal: String, from fen: String, _ index: ReferenceIndex) -> [String]? {
  let replies = (index.entries[positionKey(fen)]?.moves ?? []).sorted { $0.games > $1.games }
  for reply in replies {
    guard let next = applySan(fen, reply.san) else { continue }
    if positionKey(next.after) == goal { return [reply.san] }
    for move in index.entries[positionKey(next.after)]?.moves ?? [] {
      if let last = applySan(next.after, move.san), positionKey(last.after) == goal { return [reply.san, move.san] }
    }
  }
  return nil
}

/// Your moves in a playbook: the positions where you chose.
public func yourMoves(_ rep: Playbook) -> [RepMove] {
  nodesInOrder(rep).filter { fenTurn($0.fenBefore) == rep.color }
}

/// The positions a scan looks at: every move of yours, in every playbook. A
/// position met by two move orders is one decision, so it is looked at once.
public func tidyPositions(_ reps: [Playbook]) -> [(rep: Playbook, node: RepMove)] {
  var out: [(rep: Playbook, node: RepMove)] = []
  for rep in reps {
    var seen = Set<String>()
    for node in yourMoves(rep) where seen.insert("\(node.key)|\(node.san)").inserted { out.append((rep, node)) }
  }
  return out
}

/// Most moves removed first, then the earliest.
public func sortFinds(_ finds: [TidyFind]) -> [TidyFind] {
  finds.jsSorted { a, b in
    let d = b.removes - a.removes
    return Double(d != 0 ? d : a.path.count - b.path.count)
  }
}

/// Switch your move at a position: the new move becomes yours there, and the
/// old one goes with everything under it. Nil when the move is not legal.
public func switchMove(_ rep: Playbook, _ nodeId: String, _ san: String) -> Playbook? {
  guard let old = rep.nodes[nodeId], let added = addMove(rep, old.parentId, san, .tidy) else { return nil }
  return removeSubtree(setPreferred(added.rep, added.node.id), nodeId)
}
