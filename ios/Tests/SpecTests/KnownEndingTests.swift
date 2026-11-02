import ChessCore
import Model
import Testing

/// Endings settled on sight, past the tablebases' four pieces.

@Test func lucenaIsAWinOnlyWithTheKingCutOff() {
  let lucena = knownEnding("3K4/3P1k2/8/8/8/8/2r5/4R3 w - - 0 1")
  #expect(lucena == KnownEnding(name: "Lucena", winner: .w))
  #expect(lucena?.result(for: .b) == .loss)
  // The rook on a1 cuts nothing off.
  #expect(knownEnding("3K4/3P1k2/8/8/8/8/2r5/R7 w - - 0 1") == nil)
}

@Test func philidorHoldsWithTheRookOnTheSixth() {
  #expect(knownEnding("4k3/8/r7/4K3/4P3/8/8/7R w - - 0 1") == KnownEnding(name: "Philidor", winner: nil))
  // Their rook still on the back rank: not yet the Philidor.
  #expect(knownEnding("r3k3/8/8/4K3/4P3/8/8/7R w - - 0 1") == nil)
}

@Test func wrongBishopCantDriveTheKingFromTheCorner() {
  #expect(knownEnding("k7/8/P7/P1K1B3/8/8/8/8 w - - 0 1")?.name == "Wrong bishop")
  // A light bishop covers a8.
  #expect(knownEnding("k7/8/P7/P1KB4/8/8/8/8 w - - 0 1") == nil)
}

@Test func oppositeBishopsHoldWithTheKingBlocking() {
  #expect(knownEnding("8/3kb3/8/3P4/2B1K3/8/8/8 w - - 0 1") == KnownEnding(name: "Opposite bishops", winner: nil))
  #expect(knownEnding("4b3/3k4/8/3P4/2B1K3/8/8/8 w - - 0 1") == nil)
}

@Test func aPieceThatCanBeTakenIsNoKnownEnding() {
  // The Lucena, but Black's rook can take White's.
  #expect(knownEnding("3K4/3P1k2/8/8/8/8/8/2r1R3 b - - 0 1") == nil)
}
