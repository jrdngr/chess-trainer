import Book
import ChessCore
import Shared

/// What Growth's lobby and sitting read besides the rows: `src/model/growth.ts`
/// (`reachesOpening`, `enginePositions`, `needsEngine`) and the lobby's
/// choices from `src/model/modes.ts`.

/// "Worth answering": the share of games a reply needs, most selective first.
public let SHARE_STEPS: [Double] = [3, 1, 0.2]
/// "How deep", in plies.
public let GROWTH_DEPTHS = [8, 12, 18]

/// A share step as the lobby labels it.
public func shareLabel(_ share: Double) -> String {
  share >= 1 ? "\(JS.string(share))% and up" : "Anything played"
}

/// Whether a side's tree has any line inside an opening already.
public func reachesOpening(_ rep: Repertoire, _ tree: OpeningTree, _ node: OpeningNode) -> Bool {
  if node.depth == 0 { return true }
  let inside = regionOf(tree, node).inside
  return rep.nodes.values.contains { inside.contains(positionKey($0.fenAfter)) }
}

/// The positions past the book at the ends of your lines the engine has not been asked about yet.
public func enginePositions(_ rep: Repertoire, _ index: ReferenceIndex, _ opts: GrowthOptions = GrowthOptions()) -> [String] {
  var out: [String] = []
  walkChoices(rep, index, opts) { choice in
    if choice.bookless && engineReplies(choice.fen) == nil { out.append(choice.fen) }
  }
  return out
}

/// Whether a position needs the engine before a run can offer or play anything there.
public func needsEngine(_ index: ReferenceIndex, _ fen: String) -> Bool {
  popularReplies(index, fen, 0).isEmpty && engineReplies(fen) == nil
}
