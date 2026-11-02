import ChessCore
import Foundation
import Model
import Testing

/// Endgame mode: the library, fresh basic-mate setups, the schedule and how a round ends.

@Test func libraryPositionsAreEndgamesWithYouToMove() {
  for entry in ENDGAME_LIBRARY {
    #expect(ENDGAME_FAMILIES.contains { $0.id == entry.family }, "\(entry.id)")
    #expect(entry.intro != nil, "\(entry.id)")
    guard let fen = entry.fen else {
      #expect(entry.setup != nil, "\(entry.id)")
      continue
    }
    #expect(isEndgame(fen), "\(entry.id)")
    #expect(!positionStatus(fen).gameOver, "\(entry.id)")
  }
  // The rook endings are the known ones: Lucena to win, Philidor to hold.
  let lucena = ENDGAME_LIBRARY.first { $0.id == "rook-lucena" }!
  #expect(knownEnding(lucena.fen!)?.result(for: fenTurn(lucena.fen!)) == .win)
  let philidor = ENDGAME_LIBRARY.first { $0.id == "rook-philidor" }!
  #expect(knownEnding(philidor.fen!)?.result(for: fenTurn(philidor.fen!)) == .draw)
}

@Test func basicMateSetupsAreLegalAndQuiet() {
  let rand = mulberry32(7)
  for kind in BasicMate.allCases {
    for _ in 0..<40 {
      let fen = basicMateSetup(kind, rand)
      #expect(fenTurn(fen) == .w)
      let pieces = piecesFromFen(fen)
      let white = pieces.filter { $0.color == .w }.map(\.type.rawValue).sorted().joined()
      #expect(pieces.filter { $0.color == .b }.map(\.type) == [.k], "\(fen)")
      #expect(white == (kind == .queen ? "kq" : kind == .rook ? "kr" : "bbk"), "\(fen)")
      #expect(!positionStatus(fen.replacingOccurrences(of: " w ", with: " b ")).check, "\(fen)")
      #expect(!positionStatus(fen).gameOver, "\(fen)")
      // Nothing of yours stands next to their king.
      let them = coordsOf(kingSquare(fen, .b)!)
      for p in pieces where p.color == .w {
        let at = coordsOf(p.square)
        #expect(max(abs(at.0 - them.0), abs(at.1 - them.1)) >= 2, "\(fen)")
      }
    }
  }
}

private func coordsOf(_ square: String) -> (Int, Int) {
  let u = Array(square.utf8)
  return (Int(u[0]) - 97, Int(u[1]) - 49)
}

@Test func successesSpreadOutAndMissesComeBack() {
  var record = EndgameRecord()
  let entry = ENDGAME_LIBRARY[0]
  record.review(entry, success: true, mission: true, now: 0)
  #expect(record.cards[entry.id]?.due == DAY_MS)
  record.review(entry, success: true, mission: false, now: DAY_MS)
  #expect(record.cards[entry.id]?.interval == 2.5)
  #expect(record.ratings[entry.family] == 2 * ENDGAME_SUCCESS_POINTS + ENDGAME_MISSION_POINTS)
  record.review(entry, success: false, mission: false, now: 5 * DAY_MS)
  #expect(record.cards[entry.id]?.due == 5 * DAY_MS)
  #expect(record.cards[entry.id]?.lapses == 1)
  #expect(record.due(5 * DAY_MS).map(\.id) == [entry.id])
  // A family's rating never drops below zero.
  var fresh = EndgameRecord()
  fresh.review(entry, success: false, mission: false, now: 0)
  #expect(fresh.ratings[entry.family] == 0)
  #expect(fresh.rank(entry.family).heldLabel == UNRATED.name)
}

@Test func theNextPositionIsTheFirstDueThenTheFirstNew() {
  var record = EndgameRecord()
  #expect(record.next(0)?.id == ENDGAME_LIBRARY[0].id)
  record.review(ENDGAME_LIBRARY[0], success: true, mission: true, now: 0)
  #expect(record.next(0)?.id == ENDGAME_LIBRARY[1].id)
  record.review(ENDGAME_LIBRARY[3], success: false, mission: false, now: 0)
  #expect(record.next(0)?.id == ENDGAME_LIBRARY[3].id)
}

@Test func savedEndgamesAreKeptOncePerPosition() {
  var record = EndgameRecord()
  let fen = "8/8/4k3/8/4K3/8/4P3/8 w - - 0 40"
  record.save(SavedEndgame(id: "a", fen: fen, goal: .win, name: "Italian Game", at: 1))
  record.save(SavedEndgame(id: "b", fen: fen.replacingOccurrences(of: "0 40", with: "3 52"), goal: .win, name: "Italian Game", at: 2))
  #expect(record.saved.map(\.id) == ["a"])
  #expect(record.entries.last?.family == "games")
  #expect(record.entries.last?.mission == .queenPawn)
  // Their king on a different square each time: a new position each time.
  for i in 0..<(SAVED_ENDGAMES_CAP + 5) {
    let rows = (0..<8).map { r in r == 7 - i / 8 ? (i % 8 == 0 ? "k7" : "\(i % 8)k\(i % 8 == 7 ? "" : "\(7 - i % 8)")") : "8" }
    record.save(SavedEndgame(id: "\(i)", fen: rows.joined(separator: "/") + " w - - 0 1", goal: .hold, name: "", at: 0))
  }
  #expect(record.saved.count == SAVED_ENDGAMES_CAP)
  #expect(record.saved.first?.id == "\(SAVED_ENDGAMES_CAP + 4)")
}

@Test func roundsEndAtTheGoal() {
  let queen = ENDGAME_LIBRARY.first { $0.id == "mate-queen" }!
  // Mate delivered inside the mission's count, and past it.
  let mated = "k7/1Q6/1K6/8/8/8/8/8 b - - 0 1"
  #expect(endgameOutcome(queen, mated, you: .w, yourMoves: 6, promoted: false, stillWon: true) == .success(text: "Checkmate", mission: true))
  #expect(endgameOutcome(queen, mated, you: .w, yourMoves: 12, promoted: false, stillWon: true) == .success(text: "Checkmate", mission: false))
  // Stalemate gives the win away.
  #expect(endgameOutcome(queen, "k7/2Q5/1K6/8/8/8/8/8 b - - 0 1", you: .w, yourMoves: 6, promoted: false, stillWon: false) == .failure(text: "Stalemate"))
  #expect(endgameOutcome(queen, "k7/8/1K6/8/8/8/8/2Q5 b - - 0 1", you: .w, yourMoves: 6, promoted: false, stillWon: true) == nil)

  let hold = ENDGAME_LIBRARY.first { $0.id == "kp-opposition" }!
  #expect(endgameOutcome(hold, "8/8/4k3/8/8/4K3/4P3/8 b - - 0 1", you: .b, yourMoves: 15, promoted: false, stillWon: false) == .success(text: "Draw held", mission: true))
  #expect(endgameOutcome(hold, "8/8/4k3/8/8/4K3/4P3/8 b - - 0 1", you: .b, yourMoves: 14, promoted: false, stillWon: false) == nil)
  // The pawn taken: bare kings, a draw held.
  #expect(endgameOutcome(hold, "8/8/4k3/8/8/4K3/8/8 w - - 0 1", you: .b, yourMoves: 3, promoted: false, stillWon: false) == .success(text: "Draw held", mission: true))

  let pawn = ENDGAME_LIBRARY.first { $0.id == "kp-square" }!
  #expect(endgameOutcome(pawn, "Q7/8/8/8/8/8/5k2/7K b - - 0 1", you: .w, yourMoves: 4, promoted: true, stillWon: true) == .success(text: "Queened", mission: true))
  #expect(endgameOutcome(pawn, "Q7/8/8/8/8/8/5k2/7K b - - 0 1", you: .w, yourMoves: 4, promoted: true, stillWon: false) == nil)
}

@Test func endgamesSaveWithTheState() throws {
  var state = AppState()
  state.endgames.review(ENDGAME_LIBRARY[0], success: true, mission: true, now: 0)
  state.endgames.sawIntro(ENDGAME_LIBRARY[0].id)
  let data = try JSONEncoder().encode(state)
  #expect(try JSONDecoder().decode(AppState.self, from: data) == state)
  // A save from before Endgame mode starts with an empty record.
  let old = try JSONDecoder().decode(AppState.self, from: Data("{}".utf8))
  #expect(old.endgames == EndgameRecord())
}
