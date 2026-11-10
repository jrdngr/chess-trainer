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

/// White's rows sit under their first move, and the answers to the Queen's Gambit under its name.
@Test func playbookGroupsNestRepliesToYourOpening() {
  let white = rep(.w, [
    "e4 e5 Nf3 Nc6 Bb5",
    "e4 c5 c3",
    "d4 d5 c4 e6 Nc3",
    "d4 d5 c4 dxc4 e3",
    "d4 d5 c4 c6 Nf3",
    "d4 Nf6 c4 c5 d5",
  ])
  let tree = openingTree(bookIndex)
  let groups = playbookGroups(playbookRows(white, bookIndex), tree)
  #expect(groups.map(\.move).sorted() == ["1.d4", "1.e4"])
  let byMove = Dictionary(uniqueKeysWithValues: groups.map { ($0.move, $0.entries) })
  func describe(_ entry: PlaybookEntry) -> String {
    switch entry {
    case .row(let row): row.name
    case .family(let name, _, let rows): "\(name): " + rows.map { nameUnder(name, $0.name) }.sorted().joined(separator: ", ")
    }
  }
  #expect(byMove["1.e4"]!.map(describe).sorted() == ["Ruy Lopez", "Sicilian Defence"])
  #expect(byMove["1.d4"]!.map(describe).sorted() == ["Benoni Defence", "Queen's Gambit: Accepted, Declined, Slav Defence"])
}
