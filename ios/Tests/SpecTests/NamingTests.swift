import Book
import ChessCore
import Model
import Testing

/// spec/cases/functions/naming.json
@Test func naming() throws {
  let tree = openingTree(bookIndex)
  try check("naming", [
    "core.positionKey": { positionKey($0[0].string).json },
    "core.sansToMoveText": { sansToMoveText(line($0[0].string)).json },
    "openingTree.moveLabel": { moveLabel(line($0[0].string)).json },
    "reference.deepestName": { a in
      deepestName(bookIndex, line(a[0].string)).map { obj(["eco": $0.eco, "name": $0.name, "ply": $0.ply]) } ?? .null
    },
    "reference.namesAlong": { a in
      .array(namesAlong(bookIndex, line(a[0].string)).map { obj(["eco": $0.eco, "name": $0.name, "ply": $0.ply]) })
    },
    "reference.familyName": { familyName(bookIndex, $0[0].string).json },
    "reference.formatGameCount": { formatGameCount($0[0].number).json },
    "openingTree.deepestNodeAlong": { deepestNodeAlong(tree, line($0[0].string))?.id.json ?? .null },
    "openingTree.deepestNodeWithin": { a in
      deepestNodeWithin(tree, nodeById(tree, a[0].string), line(a[1].string)).id.json
    },
    "openingTree.lineStatus": { a in
      lineStatus(tree, nodeById(tree, a[0].string), line(a[1].string)).rawValue.json
    },
    "openingTree.ancestorsOf": { ancestorsOf(tree, $0[0].string).map(\.id).json },
    "openingTree.nodeById": { a in
      let node = nodeById(tree, a[0].string)
      return obj(["id": node.id, "name": node.name, "parentId": node.parentId, "depth": node.depth, "custom": node.custom])
    },
    "openingTree.node": { a in
      let node = nodeById(tree, a[0].string)
      return obj(["name": node.name, "eco": node.eco, "parentId": node.parentId, "depth": node.depth, "games": node.games, "children": node.children.count])
    },
  ])
}
