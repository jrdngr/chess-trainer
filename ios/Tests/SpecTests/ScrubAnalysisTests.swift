import ChessCore
import Model
import Testing

/// Reading PGN and scoring imported games: castling written with zeros, lone
/// annotation glyphs, games set up from a position, and unfinished results.

@Test func pgnCastlingWithZeros() throws {
  let game = try #require(parsePgn("1. e4 e5 2. Nf3 Nc6 3. Bc4 Bc5 4. 0-0 Nf6 5. d3 d6 6. Nc3 Bg4 7. h3 Bh5 8. Be3 Qd7 9. a3 0-0-0").first)
  #expect(pgnMainline(game) == ["e4", "e5", "Nf3", "Nc6", "Bc4", "Bc5", "O-O", "Nf6", "d3", "d6", "Nc3", "Bg4", "h3", "Bh5", "Be3", "Qd7", "a3", "O-O-O"])
}

@Test func pgnLoneAnnotationGlyphIsNoMove() throws {
  let game = try #require(parsePgn("1. e4 !? e5 2. Nf3 ! Nc6").first)
  #expect(pgnMainline(game) == ["e4", "e5", "Nf3", "Nc6"])
}

@Test func importLeavesOutGamesSetUpFromAPosition() {
  let setUp = "[White \"tester\"]\n[Black \"x\"]\n[SetUp \"1\"]\n[FEN \"4k3/8/8/8/8/8/4P3/4K3 w - - 0 1\"]\n\n1. e4 Kd7 *"
  #expect(gamesFromPgn(setUp, "tester").isEmpty)
  let standard = "[White \"tester\"]\n[Black \"x\"]\n[FEN \"\(START_FEN)\"]\n\n1. e4 e5 *"
  #expect(gamesFromPgn(standard, "tester").map(\.moves) == [["e4", "e5"]])
}

@Test func unfinishedGameScoresAsDrawForEitherSide() throws {
  for color in [Color.w, .b] {
    let game = ImportedGame(
      id: "g", source: .pgn, white: "a", black: "b", result: "*", userColor: color, moves: ["e4", "e5"])
    let tree = buildPlayerTree([game], color)
    let root = try #require(tree.nodes[positionKey(START_FEN)])
    #expect([root.wins, root.draws, root.losses] == [0, 1, 0])
  }
}
