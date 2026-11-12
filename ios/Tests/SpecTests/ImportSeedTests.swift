import ChessCore
import Model
import Testing

/// The import list: which of your openings it offers, how deep, and which start checked.

private func games(_ color: Color, _ times: Int, _ moves: String) -> [ImportedGame] {
  (0..<times).map { i in
    ImportedGame(
      id: "\(color.rawValue)\(moves)\(i)", site: .lichess, white: color == .w ? "me" : "them",
      black: color == .b ? "me" : "them", result: "1-0", userColor: color, moves: line(moves))
  }
}

/// 20 games as White: the Italian most, a Sicilian and a Queen's Gambit less.
/// 10 as Black: a Najdorf against 1.e4 and a Nimzo-Indian against 1.d4.
private let ARCHIVE =
  games(.w, 8, "e4 e5 Nf3 Nc6 Bc4 Bc5 c3 Nf6 d4 exd4")
  + games(.w, 4, "e4 e5 Nf3 Nc6 Bc4 Nf6 Ng5 d5 exd5 Na5")
  + games(.w, 4, "e4 c5 Nf3 d6 d4 cxd4 Nxd4 Nf6 Nc3 a6")
  + games(.w, 4, "d4 d5 c4 e6 Nc3 Nf6")
  + games(.b, 6, "e4 c5 Nf3 d6 d4 cxd4 Nxd4 Nf6 Nc3 a6")
  + games(.b, 4, "d4 Nf6 c4 e6 Nc3 Bb4")

private func lines(_ row: SeedRow) -> [String] { row.lines.map { $0.joined(separator: " ") }.sorted() }

@Test func seedDepthFollowsHowOftenYouPlayIt() throws {
  let rows = seedRows(ARCHIVE, bookIndex, [])
  let italian = try #require(rows.first { $0.color == .w && $0.lines.contains { $0.starts(with: line("e4 e5 Nf3 Nc6 Bc4")) } })
  // 8 of 20 games reach move 5's d4 (25% needs 5); the 4 Two Knights games stop before exd5.
  #expect(lines(italian).contains("e4 e5 Nf3 Nc6 Bc4 Bc5 c3 Nf6 d4"))
  #expect(lines(italian).contains("e4 e5 Nf3 Nc6 Bc4 Nf6 Ng5"))
  // The Sicilian's 4 games clear move 4's bar (20% of 20) but not move 5's.
  let sicilian = try #require(rows.first { $0.color == .w && $0.lines.contains { $0.starts(with: line("e4 c5")) } })
  #expect(lines(sicilian) == ["e4 c5 Nf3 d6 d4 cxd4 Nxd4"])
}

@Test func seedChecksOneMostPlayedOpeningPerEmptySlot() {
  let rows = seedRows(ARCHIVE, bookIndex, [])
  let checked = rows.filter(\.checked)
  #expect(Set(checked.map(\.slot)) == [.white, .against("e4"), .against("d4")])
  #expect(checked.first { $0.slot == .white }?.lines.allSatisfy { $0.starts(with: line("e4 e5")) } == true)
  // Checked rows lead; the rest follow unchecked.
  #expect(rows.prefix(checked.count).allSatisfy { $0.checked })
  #expect(rows.dropFirst(checked.count).allSatisfy { !$0.checked })
}

@Test func seedLeavesOutOpeningsThePlaybookHasAndChecksNothingInAFilledSlot() {
  let tree = openingTree(bookIndex)
  var state = AppState()
  // Classical: the Italian as White, 1...e5 and the Queen's Gambit Declined as Black.
  state.seed(tree, STARTER_SETS[0])
  let rows = seedRows(ARCHIVE, bookIndex, state.playbookList)
  #expect(rows.allSatisfy { !$0.checked })
  #expect(!rows.contains { $0.color == .w && $0.lines.contains { $0.starts(with: line("e4 e5 Nf3 Nc6 Bc4")) } })
  // The same name on the other side is a different opening: your Queen's Gambit as White still shows.
  #expect(rows.contains { $0.color == .w && $0.lines.contains { $0.starts(with: line("d4 d5 c4")) } })
  #expect(rows.contains { $0.color == .b && $0.slot == .against("e4") })
}

@Test func seedCutsMistakesAndMovesStrongPlayersRarelyChoose() throws {
  // Bc4 called a mistake: the Italian line stops before it.
  let fen = after("e4 e5 Nf3 Nc6")
  let cut = seedRows(ARCHIVE, bookIndex, [], lost: ["\(positionKey(fen)) Bc4": 120])
  #expect(!cut.flatMap(\.lines).contains { $0.starts(with: line("e4 e5 Nf3 Nc6 Bc4")) })
  // 2.Qh5 is under 5% of the book's games after 1.e4 e5, however often you play it.
  let rows = seedRows(games(.w, 10, "e4 e5 Qh5 Nc6 Bc4 g6"), bookIndex, [])
  #expect(rows.flatMap(\.lines).map { $0.joined(separator: " ") } == ["e4"])
}

@Test func seedOffersOpeningsBelowTheBarUnchecked() {
  // 4 of 50 White games play 1.c4: under the 10% bar, over half of it and the 4-game floor.
  let rows = seedRows(games(.w, 46, "e4 e5 Nf3 Nc6 Bb5 a6") + games(.w, 4, "c4 e5 Nc3 Nf6"), bookIndex, [])
  #expect(rows.first?.checked == true)
  let english = rows.first { $0.lines.contains { $0.first == "c4" } }
  #expect(english?.checked == false)
  #expect(english.map(lines) == ["c4 e5 Nc3"])
}

@Test func seedRowsGoIntoThePlaybookAsImportedMoves() throws {
  var state = AppState()
  let rows = seedRows(ARCHIVE, bookIndex, []).filter(\.checked)
  let added = state.addSeedRows(rows)
  #expect(added > 0)
  let white = try #require(state.playbookList.first { $0.color == .w })
  let tip = try #require(nodeAtLine(white, line("e4 e5 Nf3 Nc6 Bc4 Bc5 c3 Nf6 d4")))
  #expect(tip.source == .import)
  // Once added, the same games offer nothing checked and none of those openings again.
  let again = seedRows(ARCHIVE, bookIndex, state.playbookList)
  #expect(again.allSatisfy { !$0.checked })
  #expect(Set(again.map(\.id)).isDisjoint(with: rows.map(\.id)))
}

@Test func seedMovesAreYourOwnOnceEach() {
  let rows = seedRows(games(.b, 6, "e4 c5 Nf3 d6 d4 cxd4"), bookIndex, [])
  let moves = seedMoves(rows + rows)
  #expect(moves.map(\.san) == ["c5", "d6", "cxd4"])
  #expect(moves.allSatisfy { fenTurn($0.fen) == .b })
}
