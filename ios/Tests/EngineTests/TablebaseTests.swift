import ChessCore
import Model
import Testing
@testable import Engine

/// The bundled Syzygy tables, probed through Fathom.

/// King and pawn against king: your king one square ahead of its pawn, the kings face to face.
private let OPPOSITION = "8/8/4k3/8/4K3/4P3/8/8"

@Test func oppositionDecidesKingAndPawn() {
  // White to move must give up the opposition: Black holds the draw.
  #expect(Tablebase.probe("\(OPPOSITION) w - - 0 1") == .draw)
  // Black to move must give way, and White's king reaches a key square.
  #expect(Tablebase.probe("\(OPPOSITION) b - - 0 1") == .loss)
  #expect(Tablebase.probe("\(OPPOSITION) b - - 0 1", for: .w) == .win)
  // With the pawn on the sixth and its king behind it, Black holds whoever moves.
  #expect(Tablebase.probe("4k3/8/4P3/4K3/8/8/8/8 b - - 0 1") == .draw)
}

@Test func basicMatesAndBareMinorsAreKnown() {
  #expect(Tablebase.probe("4k3/8/8/8/8/8/8/R3K3 b - - 0 1") == .loss)
  #expect(Tablebase.probe("4k3/8/8/8/8/8/8/R3K3 b - - 0 1", for: .w) == .win)
  #expect(Tablebase.probe("8/8/4k3/8/8/8/8/3NK3 w - - 0 1") == .draw)
}

@Test func positionsPastTheTablesAreUnknown() {
  // Lucena has five pieces.
  #expect(Tablebase.probe("3K4/3P1k2/8/8/8/8/2r5/4R3 w - - 0 1") == nil)
  // Castling rights left.
  #expect(Tablebase.probe("4k3/8/8/8/8/8/8/R3K3 w Q - 0 1") == nil)
}

@Test func libraryGoalsMatchTheTables() {
  // Every library position the tables cover asks for the result they give: Win it is a win, Hold it a draw.
  for entry in ENDGAME_LIBRARY {
    guard let fen = entry.fen, let result = Tablebase.probe(fen) else { continue }
    #expect(result == (entry.goal == .win ? .win : .draw), "\(entry.id)")
  }
}
