import Foundation
import ChessCore
import Shared

/// One side and the region it covers.
public struct SideRegion: Sendable {
  public var side: Color
  public var node: OpeningNode
}

/// The regions a selection covers, per side.
public func regionsBySide(_ tree: OpeningTree, _ selection: Selection) -> [SideRegion] {
  let node = nodeById(tree, selection.opening)
  return colorsOf(selection.color).map { SideRegion(side: $0, node: node) }
}

/// Each region a selection covers, paired with that side's repertoire, and
/// the results merged without repeats: what one region's call gives, for all of them.
public func acrossRegions<T>(
  _ regions: [SideRegion], _ reps: [Repertoire], _ each: (Repertoire, OpeningNode) -> [T], _ key: (T) -> String
) -> [T] {
  var seen = Set<String>()
  var out: [T] = []
  for region in regions {
    for rep in reps where rep.color == region.side {
      for item in each(rep, region.node) where seen.insert(key(item)).inserted { out.append(item) }
    }
  }
  return out
}
