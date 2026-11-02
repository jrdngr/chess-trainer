import ChessCore
import Model
import Testing
@testable import Engine

/// The bundled Syzygy tables, probed through Fathom.

/// King and pawn against king, the pawn on the sixth with its king behind it.
private let OPPOSITION = "4k3/8/4P3/4K3/8/8/8/8"

@Test func oppositionDecidesKingAndPawn() {
  // White to move can't shake the king off: e7+ only stalemates.
  #expect(Tablebase.probe("\(OPPOSITION) w - - 0 1") == .draw)
  // Black to move must give way, and the pawn queens.
  #expect(Tablebase.probe("\(OPPOSITION) b - - 0 1") == .loss)
  #expect(Tablebase.probe("\(OPPOSITION) b - - 0 1", for: .w) == .win)
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
