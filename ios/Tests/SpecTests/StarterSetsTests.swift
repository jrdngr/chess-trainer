import ChessCore
import Model
import Testing

/// The starter set functions in spec/cases/functions/onboarding.json.
@Test func starterSets() throws {
  let tree = openingTree(bookIndex)
  try check("onboarding", [
    "starterSets.set": { a in
      let set = STARTER_SETS.first { $0.id == a[0].string }!
      return obj([
        "name": set.name, "description": set.description,
        "openings": JSON.array(setOpenings(set).map { o in
          obj(["slot": o.slot.rawValue, "id": o.id, "name": o.label ?? nodeById(tree, o.id).name, "color": o.color.rawValue,
               "moves": countOwnMoves([(line(o.id), o.color)])])
        }),
        "moves": countOwnMoves(setOpenings(set).map { (line($0.id), $0.color) }),
      ])
    },
    "starterSets.countOwnMoves": { a in countOwnMoves(a[0].array.map { (line($0[0].string), color($0[1])) }).json },
    "starterSets.seedFor": { a in
      let sans = line(a[0].string)
      return obj(["sans": sans, "color": (a[1].stringOrNil.map { Color(rawValue: $0)! } ?? playerOf(sans)).rawValue])
    },
  ], only: ["starterSets.set", "starterSets.countOwnMoves", "starterSets.seedFor"])
}
