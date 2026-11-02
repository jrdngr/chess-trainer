import ChessCore
import Model
import Testing

/// The Pawns, Pieces and Kings lenses once a game reaches an endgame.

private let PAWNS = "8/8/4k1p1/P3P2p/5P2/6K1/8/8 w - - 0 1"
private let KP = "8/8/4k3/8/4K3/8/4P3/8 w - - 0 1"
private let LUCENA = "3K4/3P1k2/8/8/8/8/2r5/4R3 w - - 0 1"
private let BAD_BISHOP = "1r4k1/4b1p1/3p1p2/1P1Kp3/6P1/8/7N/1R6 w - - 0 1"

@Test func passersAreNamedByKind() {
  let letters = lensMarks(.pawns, PAWNS, .w).letters ?? []
  let named = Dictionary(uniqueKeysWithValues: letters.map { ($0.square, $0.text) })
  // a5 is far from every black pawn; f4 guards e5; g6 guards h5.
  #expect(named == ["a5": "O", "e5": "P", "h5": "P"])
  #expect(letters.first { $0.square == "h5" }?.tone == "theirs")
}

@Test func thePawnSquareRunsTowardTheKing() {
  // Three ranks to go, so three files across, toward the king on e6.
  #expect(lensMarks(.pawns, PAWNS, .w).boxes?.contains(Segment(from: "a5", to: "d8")) == true)
  // A pawn on its first rank counts from one rank on.
  #expect(pawnSquare("8/8/8/8/8/8/P7/7k w - - 0 1", "a2", .w) == Segment(from: "a3", to: "f8"))
  // With a rook to stop it, the race is off.
  #expect(lensMarks(.pawns, "r7/8/4k3/P7/8/8/8/6K1 w - - 0 1", .w).boxes == [])
}

@Test func keySquaresFollowThePawn() {
  #expect(keySquares("e2", .w) == ["d4", "e4", "f4"])
  #expect(keySquares("e5", .w) == ["d6", "e6", "f6", "d7", "e7", "f7"])
  #expect(keySquares("a2", .w) == ["b7", "b8"])
  #expect(keySquares("d5", .b) == ["c3", "d3", "e3"])
}

@Test func theSideNotToMoveHoldsTheOpposition() {
  #expect(opposition(KP) == .b)
  #expect(opposition(KP.replacingOccurrences(of: " w ", with: " b ")) == .w)
  // Three files apart: no opposition.
  #expect(opposition("8/8/7k/8/4K3/8/4P3/8 w - - 0 1") == nil)
  let kings = lensMarks(.kings, KP, .w)
  #expect(kings.caption == "They have the opposition")
  #expect(kings.guides == [Guide(from: "e4", to: "e6", tone: "opposition")])
  #expect(Set(kings.tints?.map(\.square) ?? []) == ["d4", "e4", "f4"])
}

@Test func aRookBetweenKingAndPasserCutsTheKingOff() {
  let kings = heldLens(.kings, LUCENA, .w)
  #expect(kings.guides == [Guide(from: "e1", to: "e8", tone: "cutoff")])
  #expect(kings.caption == "You\u{2019}re on a key square")
  #expect(kings.focus == ["d7", "d8", "e1", "f7"])
}

@Test func endgamePiecesRateRooksBishopsAndKings() {
  let marks = lensMarks(.pieces, BAD_BISHOP, .w)
  let tone = Dictionary(uniqueKeysWithValues: (marks.rings ?? []).map { ($0.square, $0.tone) })
  // The rook behind its passer, the king in the middle.
  #expect(tone["b1"] == "good")
  #expect(tone["d5"] == "good")
  // Every black pawn on the bishop's color.
  #expect(tone["e7"] == "bad")
  #expect(Set(marks.dots ?? []).isSuperset(of: ["d6", "e5", "f6"]))
  #expect(tone["g8"] == "bad")
  #expect(marks.stars == nil)
}

@Test func middlegameLensesStayAsTheyWere() {
  let fen = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"
  #expect(lensMarks(.pawns, fen, .w) == pawnsLens(fen))
  #expect(lensMarks(.kings, fen, .w) == kingsLens(fen, .w))
}
