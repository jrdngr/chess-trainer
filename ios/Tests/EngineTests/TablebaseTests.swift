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

@Test func enPassantRightsChangeTheResult() {
  // Black saves the game only by taking en passant; without the right, Black loses.
  #expect(Tablebase.probe("8/8/8/8/3pP3/8/8/k1K5 b - e3 0 1") == .draw)
  #expect(Tablebase.probe("8/8/8/8/3pP3/8/8/k1K5 b - - 0 1") == .loss)
}

@Test func aMatedSideHasLost() {
  #expect(Tablebase.probe("7k/6Q1/6K1/8/8/8/8/8 b - - 0 1") == .loss)
  #expect(Tablebase.probe("7k/6Q1/6K1/8/8/8/8/8 b - - 0 1", for: .w) == .win)
}

@Test func positionsPastTheTablesAreUnknown() {
  // Lucena has five pieces.
  #expect(Tablebase.probe("3K4/3P1k2/8/8/8/8/2r5/4R3 w - - 0 1") == nil)
  // Castling rights left.
  #expect(Tablebase.probe("4k3/8/8/8/8/8/8/R3K3 w Q - 0 1") == nil)
}

/// Rounds of one library entry from a fixed seed, checked against the tables.
private func starts(_ entry: EndgameEntry, _ count: Int = 40) -> [String] {
  let rand = mulberry32(5)
  return (0..<count).map { _ in endgameStart(entry, rand) { Tablebase.probe($0, for: $1) } }
}

private let PAWN_ENTRIES = ENDGAME_LIBRARY.filter { $0.family == "pawn" }

@Test func pawnEndingsVaryAndGiveYouTheGoal() {
  #expect(PAWN_ENTRIES.count == 6)
  for entry in PAWN_ENTRIES {
    let fens = starts(entry)
    for fen in fens {
      // You are to move, and the tables give you the goal: Win is a win, Hold Draw a draw.
      #expect(Tablebase.probe(fen) == (entry.goal == .win ? .win : .draw), "\(entry.id) \(fen)")
      #expect(!positionStatus(fen).gameOver, "\(entry.id) \(fen)")
    }
    #expect(Set(fens.map(positionKey)).count >= 20, "\(entry.id)")
    #expect(Set(fens.map(fenTurn)).count == 2, "\(entry.id)")
    // You play the side with the pawn when winning, the bare king when holding.
    for fen in fens {
      let pawn = piecesFromFen(fen).first { $0.type == .p }!
      #expect((pawn.color == fenTurn(fen)) == (entry.goal == .win), "\(entry.id) \(fen)")
    }
  }
}

@Test func theSquareRuleDecidesTheRace() {
  for entry in PAWN_ENTRIES where entry.setup == .square {
    for fen in starts(entry) {
      let pieces = piecesFromFen(fen)
      let pawn = pieces.first { $0.type == .p }!
      let them = pieces.first { $0.type == .k && $0.color != pawn.color }!
      let (pf, pr) = (Int(Array(pawn.square.utf8)[0]) - 97, Int(Array(pawn.square.utf8)[1]) - 49)
      let (kf, kr) = (Int(Array(them.square.utf8)[0]) - 97, Int(Array(them.square.utf8)[1]) - 49)
      let queening = pawn.color == .w ? 7 : 0
      let steps = abs(queening - pr)
      let d = max(abs(kf - pf), abs(kr - queening))
      // Running, their king starts outside the square; chasing, your king starts inside it.
      if entry.goal == .win {
        #expect(d > steps, "\(fen)")
      } else {
        #expect(d <= steps + 1, "\(fen)")
      }
    }
  }
}

@Test func pawnEndingsFallBackToATextbookPosition() {
  // With no result known, no fresh position passes: the setup's own position is played.
  for entry in PAWN_ENTRIES {
    let fen = endgameStart(entry, mulberry32(3)) { _, _ in nil }
    #expect(Tablebase.probe(fen) == (entry.goal == .win ? .win : .draw), "\(entry.id) \(fen)")
  }
}
