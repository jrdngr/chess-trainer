import Foundation
import ChessCore
import Shared

/// "Any favorite": one of your favorites per round. `src/model/anyFavorite.ts`.
public let ANY_FAVORITE = "*favorites"

public func isAnyFavorite(_ selection: Selection) -> Bool {
  selection.opening == ANY_FAVORITE
}

public struct Favorite: Sendable {
  public var node: OpeningNode
  public var side: Color
}

/// Your favorites with the side each is played from, in the selection's sides.
public func favoritesIn(_ tree: OpeningTree, _ ids: [String], _ color: ColorChoice) -> [Favorite] {
  let catalog = pickerCatalog(tree)
  let sides = colorsOf(color)
  return ids
    .compactMap { tree.byId[$0] }
    .filter { $0.depth > 0 }
    .map { Favorite(node: $0, side: sideForPick(catalog, $0) ?? .w) }
    .filter { sides.contains($0.side) }
}

/// How much more the favorite played longest ago is picked than the next.
private let ODDS = 0.5

/// The favorite a round lands on: played longest ago first, each next half
/// as likely, skipping `last` while there is another.
public func pickFavorite(_ favorites: [Favorite], _ lastAt: (String) -> Double, _ last: String?, _ rand: () -> Double) -> Favorite? {
  let field = favorites.count > 1 ? favorites.filter { $0.node.id != last } : favorites
  if field.isEmpty { return nil }
  let ranked = field.jsSorted { lastAt($0.node.id) - lastAt($1.node.id) }
  let weights = ranked.indices.map { pow(ODDS, Double($0)) }
  var roll = rand() * weights.reduce(0, +)
  for (i, fav) in ranked.enumerated() {
    roll -= weights[i]
    if roll < 0 { return fav }
  }
  return ranked.last
}

/// One round's selection under Any favorite: a side, then a favorite of it.
public func resolveFavorite(_ tree: OpeningTree, _ selection: Selection, _ ids: [String], _ lastAt: (String) -> Double, _ last: String?, _ rand: () -> Double) -> Selection {
  if !isAnyFavorite(selection) { return selection }
  let all = favoritesIn(tree, ids, selection.color)
  var sides: [Color] = []
  for fav in all where !sides.contains(fav.side) { sides.append(fav.side) }
  if sides.isEmpty { return Selection(color: selection.color, opening: "") }
  let side = sides.count > 1 ? sides[Int((rand() * Double(sides.count)).rounded(.down))] : sides[0]
  let pick = pickFavorite(all.filter { $0.side == side }, lastAt, last, rand)!
  return Selection(color: pick.side == .w ? .w : .b, opening: pick.node.id)
}

/// One side and the region it covers.
public struct SideRegion: Sendable {
  public var side: Color
  public var node: OpeningNode
}

/// The regions a selection covers, per side.
public func regionsBySide(_ tree: OpeningTree, _ selection: Selection, _ ids: [String]) -> [SideRegion] {
  if !isAnyFavorite(selection) {
    let node = nodeById(tree, selection.opening)
    return colorsOf(selection.color).map { SideRegion(side: $0, node: node) }
  }
  let favorites = favoritesIn(tree, ids, selection.color)
  if favorites.isEmpty { return colorsOf(selection.color).map { SideRegion(side: $0, node: tree.root) } }
  return favorites.map { SideRegion(side: $0.side, node: $0.node) }
}
