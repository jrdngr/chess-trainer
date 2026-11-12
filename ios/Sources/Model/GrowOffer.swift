import Book
import ChessCore

/// The offer to grow, at the end of a run.

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

/// Where growing an opening starts: Growth's own pick for the opening, the
/// same one its lobby would start, past Growth's settings when there is none
/// within. Where the round ended plays no part, so a one-line opening widens
/// at its early, common replies before any line gets longer (owner, 11-01).
public func growLaunch(_ rep: Repertoire, _ index: ReferenceIndex, _ tree: OpeningTree, _ opening: OpeningNode, minShare: Double, maxPly: Int) -> GrowLaunch? {
  let region = (tree: tree, node: opening)
  if let within = recommended(growthRows([rep], index, GrowthOptions(minShare: minShare, maxPly: maxPly, region: region))) {
    return GrowLaunch(opening: opening, row: within, hole: nil, widened: nil)
  }
  for widened in [Widened(why: "rarer", minShare: 0, maxPly: maxPly), Widened(why: "deeper", minShare: 0, maxPly: .max)] {
    let opts = GrowthOptions(minShare: widened.minShare, maxPly: widened.maxPly, region: region)
    if let row = recommended(growthRows([rep], index, opts)) { return GrowLaunch(opening: opening, row: row, hole: nil, widened: widened) }
  }
  return nil
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

