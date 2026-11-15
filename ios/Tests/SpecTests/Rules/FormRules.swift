import ChessCore
import Foundation
import Model
import Testing

private func answer(_ line: String, correct: Bool = true, seconds: Double? = 1) -> MoveResult {
  MoveResult(mode: .run, line: line.isEmpty ? [] : line.split(separator: " ").map(String.init), color: .w, correct: correct, rated: true, at: 0, seconds: seconds)
}

@Suite("docs/rules/form.md") struct FormRules {
  /// Rule 1.
  @Test func anAnswersScore() {
    #expect(formScore(correct: true, seconds: 2.9) == 1)
    #expect(formScore(correct: true, seconds: 3) == 0.8)
    #expect(formScore(correct: true, seconds: 7.9) == 0.8)
    #expect(formScore(correct: true, seconds: 8) == 0.5)
    #expect(formScore(correct: false, seconds: 1) == 0)
  }

  /// Rule 2: the last 10, for the opening and every one above it.
  @Test func anOpeningKeepsItsLastTen() throws {
    let tree = openingTree(bookIndex)
    var form = FormRecord()
    let ruy = "e4 e5 Nf3 Nc6 Bb5 a6"
    for _ in 0..<4 { form.add(tree, answer(ruy, correct: false)) }
    for _ in 0..<10 { form.add(tree, answer(ruy, seconds: 9)) }
    let ruyId = try #require(deepestNodeAlong(tree, line(ruy))).id
    #expect(form.openings[ruyId] == Array(repeating: 0.5, count: 10))
    let above = ancestorsOf(tree, ruyId).map(\.id)
    #expect(above.count > 1 && above.allSatisfy { form.openings[$0]?.count == 10 })
  }

  /// Rule 3.
  @Test func barsFromTheAverage() throws {
    #expect(formBars([1, 1, 1, 1]) == nil)
    #expect(formBars([1, 1, 1, 0.8, 0]) == 2)
    #expect(formBars([1, 1, 1, 1, 0]) == 3)
    #expect(formBars([0.5, 0.5, 0.5, 0.5, 0.5]) == 2)
    #expect(formBars([0.5, 0.5, 0.5, 0.5, 0]) == 1)
    let tree = openingTree(bookIndex)
    var state = AppState()
    for i in 0..<5 { state.recordMove(tree, answer("e4 e5", seconds: Double(i))) }
    let id = try #require(deepestNodeAlong(tree, line("e4 e5"))).id
    #expect(state.form.bars(id) == 3)
  }

  /// Rule 4.
  @Test func endgamesFamiliesReadTheirLastFiveRounds() {
    #expect(endgameFormBars([true, true]) == nil)
    #expect(endgameFormBars([true, true, true]) == 3)
    #expect(endgameFormBars([false, true, true, true, true]) == 3)
    #expect(endgameFormBars([false, false, true, true, true]) == 2)
    #expect(endgameFormBars([false, false, false, true, true]) == 1)
    #expect(endgameFormBars([false, false, false, false, false, true, true, true, true]) == 3)
    var record = EndgameRecord()
    let entry = ENDGAME_LIBRARY[0]
    for success in [true, false, true, true, true, true] { record.review(entry, success: success) }
    #expect(record.results[entry.family] == [false, true, true, true, true])
    #expect(record.formBars(entry.family) == 3)
  }
}
