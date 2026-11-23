import ChessCore
import Model
import Testing

/// Reading PGN: castling written with zeros, lone annotation glyphs, and unfinished results.

@Test func pgnCastlingWithZeros() throws {
  let game = try #require(parsePgn("1. e4 e5 2. Nf3 Nc6 3. Bc4 Bc5 4. 0-0 Nf6 5. d3 d6 6. Nc3 Bg4 7. h3 Bh5 8. Be3 Qd7 9. a3 0-0-0").first)
  #expect(pgnMainline(game) == ["e4", "e5", "Nf3", "Nc6", "Bc4", "Bc5", "O-O", "Nf6", "d3", "d6", "Nc3", "Bg4", "h3", "Bh5", "Be3", "Qd7", "a3", "O-O-O"])
}

@Test func pgnLoneAnnotationGlyphIsNoMove() throws {
  let game = try #require(parsePgn("1. e4 !? e5 2. Nf3 ! Nc6").first)
  #expect(pgnMainline(game) == ["e4", "e5", "Nf3", "Nc6"])
}

/// A header whose value escapes its quotes is still a header: the moves after it load.
@Test func anEscapedQuoteInAHeaderKeepsTheGame() throws {
  let pgn = "[Event \"Titled \\\"Arena\\\"\"]\n[Site \"https://lichess.org/abc\"]\n[Result \"1-0\"]\n\n1. e4 e5 2. Nf3 Nc6 1-0"
  let game = try #require(parsePgn(pgn).first)
  #expect(game.headers["Event"] == "Titled \"Arena\"")
  #expect(pgnMainline(game) == ["e4", "e5", "Nf3", "Nc6"])
}
