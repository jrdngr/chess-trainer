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
