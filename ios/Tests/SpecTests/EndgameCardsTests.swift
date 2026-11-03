import ChessCore
import Foundation
import Model
import Testing

/// Endgame cards: every teaching line plays legally and shows what it says,
/// and the Plan lens finds the step a live position is on.

private func card(_ id: String) -> (entry: EndgameEntry, intro: EndgameIntro) {
  let entry = ENDGAME_LIBRARY.first { $0.id == id }!
  return (entry, entry.intro!)
}

@Test func everyCardLinePlaysLegally() {
  for entry in ENDGAME_LIBRARY {
    let intro = entry.intro!
    #expect(!intro.pages.isEmpty, "\(entry.id)")
    for page in intro.pages {
      #expect(piecesFromFen(page.fen).filter { $0.type == .k }.count == 2, "\(entry.id) \(page.title)")
      var fen = page.fen
      for step in page.steps {
        guard let move = applyMove(fen, from: step.from, to: step.to, promotion: step.promotion) else {
          Issue.record("\(entry.id) \(page.title): \(step.from)-\(step.to) is not legal in \(fen)")
          break
        }
        fen = move.after
        // A caption that names a check, mate or stalemate is borne out by the board.
        let status = positionStatus(fen)
        let named = (step.caption.split(separator: " ").first.map(String.init) ?? "").trimmingCharacters(in: CharacterSet(charactersIn: ".,"))
        if named.hasSuffix("#") { #expect(status.checkmate, "\(entry.id) \(page.title) \(named)") }
        else if named.hasSuffix("+") { #expect(status.check && !status.checkmate, "\(entry.id) \(page.title) \(named)") }
        if step.caption.contains("stalemate") { #expect(status.stalemate, "\(entry.id) \(page.title)") }
      }
      #expect(page.after(page.steps.count).fen == fen, "\(entry.id) \(page.title)")
    }
  }
}

@Test func stalematePagesShowStalemate() {
  for id in ["mate-queen", "mate-bishops"] {
    let page = card(id).intro.pages.first { $0.title == "Watch for stalemate" }!
    #expect(positionStatus(page.fen).stalemate, "\(id)")
  }
}

@Test func cardMarksNameRealSquares() {
  let squares = Set("abcdefgh".flatMap { f in (1...8).map { "\(f)\($0)" } })
  for entry in ENDGAME_LIBRARY {
    for page in entry.intro!.pages {
      let marked = page.marks.flatMap(\.squares) + page.steps.flatMap { $0.marks.flatMap(\.squares) }
      #expect(marked.allSatisfy(squares.contains), "\(entry.id) \(page.title)")
    }
  }
}

/// The plan page a position is on, seen from `me`.
private func planPage(_ id: String, _ fen: String, _ me: Color) -> Int? {
  endgamePlan(card(id).entry, fen, me)?.page
}

@Test func rookMatePlanFollowsTheBox() {
  let pages = card("mate-rook").intro.pages
  // No line between the kings yet: cut it off.
  #expect(planPage("mate-rook", pages[1].fen, .w) == 1)
  // The kings face each other off the edge: check.
  let facing = endgamePlan(card("mate-rook").entry, pages[2].fen, .w)!
  #expect(facing.page == 2)
  #expect(facing.marks.tints?.contains(Tint(square: "d4", color: .amber, strength: 3)) == true)
  // Their box is ranks 5 to 8, less the a-file the rook also holds.
  let box = Set((facing.marks.tints ?? []).filter { $0.color == .red }.map(\.square))
  #expect(box.count == 28)
  #expect(box.contains("h8") && !box.contains("a8") && !box.contains("e4"))
  // On the edge with the kings facing: mate on the edge.
  #expect(planPage("mate-rook", pages[4].fen, .w) == 4)
}

@Test func queenMatePlanStopsTheQueenAtTwoSquares() {
  let pages = card("mate-queen").intro.pages
  #expect(planPage("mate-queen", pages[1].fen, .w) == 1)
  #expect(planPage("mate-queen", pages[2].fen, .w) == 2)
}

@Test func pawnPlansFollowTheKeySquaresAndTheSquare() {
  let lead = card("kp-key-squares").intro.pages[2]
  #expect(planPage("kp-key-squares", lead.fen, .w) == 0)
  #expect(planPage("kp-key-squares", lead.after(1).fen, .w) == 2)
  let hold = card("kp-square-hold").intro.pages[2]
  #expect(planPage("kp-square-hold", hold.fen, .b) == 0)
  #expect(planPage("kp-square-hold", hold.after(1).fen, .b) == 2)
  let square = endgamePlan(card("kp-square").entry, card("kp-square").intro.pages[0].fen, .w)!
  #expect(square.marks.boxes == [Segment(from: "b4", to: "f8")])
}

@Test func rookEndingPlansFollowTheTechnique() {
  let lucena = card("rook-lucena").intro.pages
  #expect(planPage("rook-lucena", lucena[2].fen, .w) == 2)
  #expect(planPage("rook-lucena", lucena[2].after(1).fen, .w) == 3)
  #expect(planPage("rook-lucena", lucena[4].fen, .w) == 4)
  let philidor = card("rook-philidor").intro.pages
  #expect(planPage("rook-philidor", philidor[0].fen, .b) == 2)
  #expect(planPage("rook-philidor", philidor[3].fen, .b) == 3)
}

@Test func savedEndgamesHaveNoPlan() {
  let saved = SavedEndgame(id: "g1", fen: "8/8/8/3k4/R7/3K4/8/8 w - - 0 1", goal: .win, name: "Game", at: 0)
  #expect(endgamePlan(saved.entry, saved.entry.fen!, .w) == nil)
}
