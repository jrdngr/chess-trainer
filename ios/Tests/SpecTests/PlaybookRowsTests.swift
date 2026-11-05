import ChessCore
import Model
import Testing

/// King's Indian move orders that `familiesIn` lists apart become one row with all their lines.
@Test func playbookRowsMergeMoveOrders() {
  let black = rep(.b, [
    "d4 Nf6 c4 g6 Nc3 Bg7 e4 d6",
    "d4 Nf6 c4 g6 g3 Bg7 Bg2 O-O",
    "d4 Nf6 Nf3 g6 c4 Bg7 Nc3 O-O",
    "e4 c5 Nf3 d6",
  ])
  let families = familiesIn(black, bookIndex)
  #expect(families.filter { $0.name == "King's Indian Defence" }.count == 3)

  let rows = playbookRows(black, bookIndex)
  #expect(rows.map(\.name) == ["King's Indian Defence", "Sicilian Defence"])
  #expect(rows[0].parts.count == 3)
  #expect(rows[0].lines == 3)
  #expect(linesOf(black, rows[0], bookIndex).map { $0.path.joined(separator: " ") }.sorted() == [
    "d4 Nf6 Nf3 g6 c4 Bg7 Nc3 O-O",
    "d4 Nf6 c4 g6 Nc3 Bg7 e4 d6",
    "d4 Nf6 c4 g6 g3 Bg7 Bg2 O-O",
  ])
}
