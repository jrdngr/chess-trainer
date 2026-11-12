import ChessCore
import Foundation
import Model
import Testing

/// Rounds of one entry, from a fixed seed. The tables are not in this target: no result is known.
private func starts(_ id: String, _ count: Int = 40) -> [String] {
  let entry = ENDGAME_LIBRARY.first { $0.id == id }!
  let rand = mulberry32(11)
  return (0..<count).map { _ in endgameStart(entry, rand) { _, _ in nil } }
}

private func coordsOf(_ square: String) -> (Int, Int) {
  let u = Array(square.utf8)
  return (Int(u[0]) - 97, Int(u[1]) - 49)
}

@Suite("docs/rules/endgames.md") struct EndgamesRules {
  /// Rule 2.
  @Test func libraryEntriesAreSetUpFreshEachRound() {
    for entry in ENDGAME_LIBRARY {
      #expect(ENDGAME_FAMILIES.contains { $0.id == entry.family }, "\(entry.id)")
      #expect(entry.intro != nil, "\(entry.id)")
      #expect(entry.fen == nil && entry.setup != nil, "\(entry.id)")
    }
  }

  /// Rule 2.
  @Test func rookEndingsVaryAndStayTheKnownEnding() {
    for (id, name, result) in [("rook-lucena", "Lucena", EndResult.win), ("rook-philidor", "Philidor", .draw)] {
      let fens = starts(id)
      for fen in fens {
        #expect(isEndgame(fen), "\(fen)")
        #expect(!positionStatus(fen).gameOver, "\(fen)")
        let known = knownEnding(fen)
        #expect(known?.name == name, "\(fen)")
        #expect(known?.result(for: fenTurn(fen)) == result, "\(fen)")
      }
      #expect(Set(fens.map(positionKey)).count >= 20, "\(id)")
      #expect(Set(fens.map(fenTurn)).count == 2, "\(id)")
    }
  }

  /// Rule 2.
  @Test func basicMatesComeInBothColors() {
    let fens = starts("mate-rook")
    #expect(Set(fens.map(fenTurn)).count == 2)
    for fen in fens {
      let you = fenTurn(fen)
      let pieces = piecesFromFen(fen)
      #expect(pieces.filter { $0.color != you }.map(\.type) == [.k], "\(fen)")
      #expect(pieces.filter { $0.color == you }.map(\.type.rawValue).sorted() == ["k", "r"], "\(fen)")
      #expect(!positionStatus(fen).gameOver, "\(fen)")
    }
  }

  /// Rule 2.
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

  /// Rules 5 and 7.
  @Test func successesSpreadOutAndMissesComeBack() {
    var record = EndgameRecord()
    let entry = ENDGAME_LIBRARY[0]
    record.review(entry, success: true, mission: true)
    #expect(record.cards[entry.id]?.dueRound == 1 + 3)
    #expect(record.due.isEmpty)
    record.review(entry, success: true, mission: false)
    #expect(record.cards[entry.id]?.interval == 7.5)
    #expect(record.cards[entry.id]?.dueRound == 2 + 8)
    #expect(record.ratings[entry.family] == 2 * ENDGAME_SUCCESS_POINTS + ENDGAME_MISSION_POINTS)
    record.review(entry, success: false, mission: false)
    #expect(record.cards[entry.id]?.dueRound == 3)
    #expect(record.cards[entry.id]?.lapses == 1)
    #expect(record.due.map(\.id) == [entry.id])
    // A family's rating never drops below zero.
    var fresh = EndgameRecord()
    fresh.review(entry, success: false, mission: false)
    #expect(fresh.ratings[entry.family] == 0)
    #expect(fresh.rank(entry.family).heldLabel == UNRATED.name)
  }

  /// Rule 6.
  @Test func theNextPositionIsTheFirstDueThenTheFirstNew() {
    var record = EndgameRecord()
    #expect(record.next?.id == ENDGAME_LIBRARY[0].id)
    record.review(ENDGAME_LIBRARY[0], success: true, mission: true)
    #expect(record.next?.id == ENDGAME_LIBRARY[1].id)
    record.review(ENDGAME_LIBRARY[3], success: false, mission: false)
    #expect(record.next?.id == ENDGAME_LIBRARY[3].id)
    // Three rounds on, the first success is due again, after the miss due since round 2.
    for entry in ENDGAME_LIBRARY[4...6] { record.review(entry, success: false, mission: false) }
    #expect(record.due.first?.id == ENDGAME_LIBRARY[3].id)
    #expect(record.due.map(\.id).contains(ENDGAME_LIBRARY[0].id))
  }

  /// Rule 3.
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

  /// Rule 3.
  @Test func aSavedEndgameStartsAFreshFiftyMoveCount() {
    // Saved deep into a game's fifty-move count: one quiet move would draw it there.
    let saved = SavedEndgame(id: "s", fen: "8/8/4k3/8/8/8/4K3/7R w - - 99 80", goal: .win, name: "", at: 0)
    let entry = saved.entry
    let move = applyUci(entry.fen!, "h1h2")!
    #expect(endgameOutcome(entry, move.after, you: .w, yourMoves: 1, promoted: false, stillWon: true) == nil)
    // No pawn of yours to queen: the win is to be mated.
    #expect(entry.mission == .mateIn(50))
  }

  /// Rule 4.
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
}
