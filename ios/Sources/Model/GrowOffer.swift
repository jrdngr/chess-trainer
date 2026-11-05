import Book
import ChessCore

/// The offer to grow, at the end of a run.

/// Clean finishes every line needs, since it last changed, before the opening is ready to grow.
public let CLEAN_FINISHES = 3

/// The opening an offer is about: the one the round started inside, the
/// selection, or the family a round from move one ended in.
public func offerOpening(_ tree: OpeningTree, _ region: OpeningNode, _ entered: OpeningNode?, _ played: [String]) -> OpeningNode {
  let within = entered ?? region
  if within.depth > 0 { return within }
  let deepest = deepestNodeWithin(tree, within, played)
  let fam = familyName(tree.index, deepest.name)
  return ancestorsOf(tree, deepest.id).first { familyName(tree.index, $0.name) == fam } ?? deepest
}

public struct LineFinishes: Sendable {
  public var tipId: String
  public var sans: [String]
  public var finishes: Int
}

/// Every line of yours inside an opening, with its clean finishes since it last changed.
public func lineFinishes(_ rep: Repertoire, _ tree: OpeningTree, _ opening: OpeningNode, _ rounds: [RoundRecord]) -> [LineFinishes] {
  let clean = rounds.filter { $0.color == rep.color && $0.perfect && !($0.line ?? []).isEmpty }
  return leafLines(rep).filter { lineStatus(tree, opening, $0.sans) == .reached }.map { line in
    let since = max(0, pathTo(rep, line.tipId).map(\.addedAt).max() ?? 0)
    let finishes = clean.filter { round in
      let l = round.line!
      return round.at > since && line.sans.count <= l.count && line.sans.indices.allSatisfy { l[$0] == line.sans[$0] }
    }.count
    return LineFinishes(tipId: line.tipId, sans: line.sans, finishes: finishes)
  }
}

/// Every line in the opening finished clean enough times since it last changed.
public func readyToGrow(_ rep: Repertoire, _ tree: OpeningTree, _ opening: OpeningNode, _ rounds: [RoundRecord]) -> Bool {
  let lines = lineFinishes(rep, tree, opening, rounds)
  return !lines.isEmpty && lines.allSatisfy { $0.finishes >= CLEAN_FINISHES }
}

/// The repertoire node a line reaches, by any move order.
private func nodeAt(_ rep: Repertoire, _ sans: [String], _ fen: String) -> String? {
  var nodeId: String?
  for san in sans {
    guard let kid = childrenOf(rep, nodeId).first(where: { $0.san == san }) else {
      let key = positionKey(fen)
      return rep.nodes.values.sorted { $0.addedAt < $1.addedAt }.first { positionKey($0.fenAfter) == key }?.id
    }
    nodeId = kid.id
  }
  return nodeId
}

/// The hole a round ended on: the opponent's last move, with you to answer and nothing prepared.
public func holeAtEnd(_ rep: Repertoire, _ index: ReferenceIndex, _ played: [String], _ maxPly: Int) -> Hole? {
  if played.isEmpty || played.count >= maxPly { return nil }
  let walked = walkSan(played)
  if walked.moves.count != played.count { return nil }
  let fen = walked.fens[played.count], before = walked.fens[played.count - 1]
  if fenTurn(fen) != rep.color { return nil }
  let key = positionKey(fen)
  if rep.nodes.values.contains(where: { $0.key == key }) { return nil }
  let path = Array(played.dropLast())
  let san = played.last!
  let book = optionsAt(index, before, 99).first { $0.san == san }
  return Hole(path: path, fen: before, san: san, share: book?.share ?? 0, games: book?.games ?? 0, after: fen, nodeId: nodeAt(rep, path, before), reach: 0)
}

/// The line end a round finished on: your own last move, theirs still to come.
public func endAtEnd(_ rep: Repertoire, _ played: [String], _ maxPly: Int) -> LineEnd? {
  if played.isEmpty || played.count >= maxPly { return nil }
  let walked = walkSan(played)
  if walked.moves.count != played.count { return nil }
  let fen = walked.fens[played.count]
  if fenTurn(fen) == rep.color { return nil }
  guard let nodeId = nodeAt(rep, played, fen) else { return nil }
  let key = positionKey(fen)
  if rep.nodes.values.contains(where: { $0.key == key }) { return nil }
  return LineEnd(path: played, fen: fen, nodeId: nodeId, reach: 0)
}

public struct Widened: Equatable, Sendable {
  /// "rarer" or "deeper".
  public var why: String
  public var minShare: Double
  public var maxPly: Int
}

/// Where a Growth run offered at the end of a round begins.
public struct GrowLaunch: Sendable {
  public var opening: OpeningNode
  public var row: GrowthRow
  public var hole: Hole?
  public var widened: Widened?
}

private func singleRow(_ rep: Repertoire, _ opening: OpeningNode, depth: Int, topShare: Double, holes: [Hole], ends: [LineEnd]) -> GrowthRow {
  GrowthRow(
    id: "\(rep.id)#\(opening.name)", repertoireId: rep.id, color: rep.color, name: opening.name, eco: nil, depth: depth,
    topShare: topShare, starred: false, urgency: 0, score: 0, holes: holes, ends: ends)
}

/// Where growing an opening starts: Growth's own pick for the opening, the
/// same one its lobby would start, past Growth's settings when there is none
/// within. Where the round ended plays no part, so a one-line opening widens
/// at its early, common replies before any line gets longer (owner, 11-01).
public func growLaunch(_ rep: Repertoire, _ index: ReferenceIndex, _ tree: OpeningTree, _ opening: OpeningNode, minShare: Double, maxPly: Int, starred: [String]) -> GrowLaunch? {
  let region = (tree: tree, node: opening)
  if let within = recommended(growthRows([rep], index, GrowthOptions(minShare: minShare, maxPly: maxPly, starred: starred, region: region))) {
    return GrowLaunch(opening: opening, row: within, hole: nil, widened: nil)
  }
  for widened in [Widened(why: "rarer", minShare: 0, maxPly: maxPly), Widened(why: "deeper", minShare: 0, maxPly: .max)] {
    let opts = GrowthOptions(minShare: widened.minShare, maxPly: widened.maxPly, starred: starred, region: region)
    if let row = recommended(growthRows([rep], index, opts)) { return GrowLaunch(opening: opening, row: row, hole: nil, widened: widened) }
  }
  return nil
}

/// Growth's pick starts on the line just played: the reply the round ended
/// on, or the reply to your last move.
public func startsOnLine(_ launch: GrowLaunch, _ played: [String]) -> Bool {
  guard let hole = firstHole(launch.row) else { return false }
  return hole.path == played || hole.path + [hole.san] == played
}

/// The end-of-round way into Growth: the opening, or this line.
public struct GrowOffer: Sendable {
  /// "opening" or "line".
  public var kind: String
  /// Why the card offers it; nil for a stub.
  public var text: String?
  public var launch: GrowLaunch
  /// Growing starts on the line just played, so the button says "Grow this line".
  public var onLine: Bool = false

  public init(kind: String, text: String?, launch: GrowLaunch, onLine: Bool = false) {
    self.kind = kind
    self.text = text
    self.launch = launch
    self.onLine = onLine
  }
}

/// What a clean end of prep earns, read after the round is logged.
public func growOfferAt(rep: Repertoire, index: ReferenceIndex, tree: OpeningTree, opening: OpeningNode, played: [String], rounds: [RoundRecord], minShare: Double, maxPly: Int, starred: [String], stub: Bool = false) -> GrowOffer? {
  func launch() -> GrowLaunch? { growLaunch(rep, index, tree, opening, minShare: minShare, maxPly: maxPly, starred: starred) }
  if stub, let launch = launch() {
    return GrowOffer(kind: "opening", text: nil, launch: launch)
  }
  if readyToGrow(rep, tree, opening, rounds), let launch = launch() {
    let more = launch.widened?.why == "rarer" ? " Grow it with rarer replies." : launch.widened != nil ? " Grow it deeper." : ""
    return GrowOffer(kind: "opening", text: "You finish every \(opening.name) line cleanly.\(more)", launch: launch)
  }
  // Offered where the round ended with room to grow, as before; it grows
  // wherever Growth's pick is, which is this line only when it is the most urgent.
  let hole = holeAtEnd(rep, index, played, .max)
  let tip = hole == nil ? endAtEnd(rep, played, .max) : nil
  if hole == nil && (tip == nil || pastTheBook(index, tip!.fen)) { return nil }
  guard let launch = launch() else { return nil }
  return GrowOffer(kind: "line", text: "Grow this line", launch: launch, onLine: startsOnLine(launch, played))
}
