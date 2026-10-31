import ChessCore
import Model
import Testing

/// The selection functions in spec/cases/functions/growth.json.
@Test func selection() throws {
  let tree = openingTree(bookIndex)
  func choice(_ j: JSON) -> ColorChoice { ColorChoice(rawValue: j.string)! }
  try check("growth", [
    "selection.colorsOf": { colorsOf(choice($0[0])).map(\.rawValue).json },
    "selection.colorLabel": { colorLabel(choice($0[0])).json },
    "selection.lineInRegion": { a in lineInRegion(tree, nodeById(tree, a[0].string), line(a[1].string)).json },
    "anyFavorite.favoritesIn": { a in
      .array(favoritesIn(tree, a[0].strings, choice(a[1])).map { obj(["id": $0.node.id, "side": $0.side.rawValue]) })
    },
    "anyFavorite.pickFavorite": { a in
      let ids = a[0].strings
      let favorites = favoritesIn(tree, ids, .random)
      let roll = a[2].number
      return pickFavorite(favorites, { Double(ids.firstIndex(of: $0) ?? -1) * 1000 }, a[1].stringOrNil, { roll })?.node.id.json ?? .null
    },
    "anyFavorite.resolveFavorite": { a in
      let ids = a[1].strings
      let rand = mulberry32(UInt32(a[2].int))
      let picked = resolveFavorite(tree, Selection(color: choice(a[0]), opening: ANY_FAVORITE), ids, { Double(ids.firstIndex(of: $0) ?? -1) }, nil, rand)
      return obj(["color": picked.color.rawValue, "opening": picked.opening])
    },
  ], only: ["selection.colorsOf", "selection.colorLabel", "selection.lineInRegion", "anyFavorite.favoritesIn", "anyFavorite.pickFavorite", "anyFavorite.resolveFavorite"])
}

/// The picker functions in spec/cases/functions/picker.json.
@Test func picker() throws {
  let tree = openingTree(bookIndex)
  let catalog = pickerCatalog(tree)
  try check("picker", [
    "picker.entry": { a in
      let e = catalog.byKey[a[0].string]!
      return obj([
        "label": e.label, "level": e.level, "side": e.side.rawValue, "sharpness": e.sharpness, "difficulty": e.difficulty,
        "games": e.games, "node": e.node.id, "exact": e.exact, "children": e.children.count,
      ])
    },
    "picker.family": { a in
      let f = catalog.familyByName[a[0].string]!
      return obj([
        "firstMove": f.firstMove.rawValue,
        "groups": f.groups.map { groups in
          JSON.array(groups.map { g in
            obj(["label": g.label, "node": g.node?.id, "sharpness": g.sharpness, "entries": g.entries.map(\.label), "alsoVia": g.alsoVia])
          })
        } ?? .null,
      ])
    },
    "picker.nameLevels": { nameLevels($0[0].string, $0[1].string).json },
    "picker.sideForPick": { a in sideForPick(catalog, tree.byId[a[0].string] ?? tree.root)?.rawValue.json ?? .null },
  ], only: ["picker.entry", "picker.family", "picker.nameLevels", "picker.sideForPick"])
}
