import ChessCore
import Foundation
import Model
import Testing

private func answer(_ line: String, correct: Bool = true, seconds: Double? = 1, color: Color = .w) -> MoveResult {
  MoveResult(mode: .run, line: line.isEmpty ? [] : line.split(separator: " ").map(String.init), color: color, correct: correct, rated: true, at: 0, seconds: seconds)
}

private func fenAfter(_ moves: String) -> String { walkSan(line(moves)).fens.last! }

/// A prep answer or miss in the event log, as a run logs it.
private func logged(_ moves: String, _ san: String, _ grade: Grade?, color: Color = .w) -> AppEvent {
  grade.map { AppEvent(kind: "prep-answer", color: color, san: san, fen: fenAfter(moves), text: "\($0)") }
    ?? AppEvent(kind: "prep-miss", color: color, san: "h3", fen: fenAfter(moves), best: san)
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

  /// Rule 3: the Playbook shows each opening's answers to your move there, read from your history.
  @Test func thePlaybookShowsFormAtYourMove() throws {
    let tree = openingTree(bookIndex)
    var state = AppState()
    state.addLine(state.ensurePlaybook(.w), line("d4 d5 c4 e6 Nc3"), .fixed(.book))
    for _ in 0..<5 { state.logEvent(logged("d4 d5", "c4", .hard)) }
    state.logEvent(logged("d4 d5 c4 e6", "Nc3", nil))
    state.logEvent(logged("d4 d5", "c4", .easy, color: .b))
    let at = state.formAtMove
    #expect(at == FormAtMove(state.events), "kept as the log records them")
    let (qpg, qg, qgd) = (positionKey(fenAfter("d4 d5")), positionKey(fenAfter("d4 d5 c4")), positionKey(fenAfter("d4 d5 c4 e6")))
    #expect(at.scores(qpg, .w) == Array(repeating: 0.5, count: 5), "where your move was asked")
    #expect(at.scores(qg, .w) == Array(repeating: 0.5, count: 5), "where your move goes")
    #expect(at.scores(qgd, .w) == [0], "a miss further down shows only there")

    let qpgNode = try #require(tree.byKey[qpg])
    let page = nodePage(state, tree, side: .w, id: qpgNode.id, line: line("d4 d5"))
    #expect(page.answers == Array(repeating: 0.5, count: 5))
  }

  /// Rule 3: form at your move outlasts the event log's cap, and a save from before it was kept builds it from its log.
  @Test func formAtYourMoveOutlastsTheLog() throws {
    var state = AppState()
    for _ in 0..<5 { state.logEvent(logged("d4 d5", "c4", .easy)) }
    for _ in 0..<EVENT_CAP { state.logEvent(AppEvent(kind: "eval", color: .w)) }
    let key = positionKey(fenAfter("d4 d5"))
    #expect(!state.events.contains { $0.kind == "prep-answer" })
    #expect(state.formAtMove.scores(key, .w) == Array(repeating: 1, count: 5))
    var old = AppState()
    for _ in 0..<5 { old.logEvent(logged("d4 d5", "c4", .easy)) }
    var json = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(old)) as? [String: Any])
    json["formAtMove"] = nil
    let decoded = try JSONDecoder().decode(AppState.self, from: JSONSerialization.data(withJSONObject: json))
    #expect(decoded.formAtMove.scores(key, .w) == Array(repeating: 1, count: 5))
  }

  /// Rule 4.
  @Test func formIsTheAverage() throws {
    #expect(formOf([1, 1, 1, 1]) == nil)
    #expect(abs(try #require(formOf([1, 1, 1, 0.8, 0])) - 0.76) < 1e-9)
    #expect(abs(try #require(formOf([0.5, 0.5, 0.5, 0.5, 0])) - 0.4) < 1e-9)
    let tree = openingTree(bookIndex)
    var state = AppState()
    for i in 0..<5 { state.recordMove(tree, answer("e4 e5", seconds: Double(i))) }
    let id = try #require(deepestNodeAlong(tree, line("e4 e5"))).id
    #expect(abs(try #require(state.form.value(id, .w)) - 0.92) < 1e-9)
  }

  /// Rule 6: White's answers and Black's answers in the same opening are kept apart.
  @Test func eachSideKeepsItsOwnForm() throws {
    let tree = openingTree(bookIndex)
    var form = FormRecord()
    for _ in 0..<5 { form.add(tree, answer("e4 e5 Nf3", color: .w)) }
    for _ in 0..<5 { form.add(tree, answer("e4 e5 Nf3", correct: false, color: .b)) }
    let id = try #require(deepestNodeAlong(tree, line("e4 e5"))).id
    #expect(form.value(id, .w) == 1)
    #expect(form.value(id, .b) == 0)
  }

  /// Rule 6: a save from before the split reads its form as White's.
  @Test func anOlderSavesFormIsWhites() throws {
    let old = #"{"openings":{"e4 e5":[1,1,1,1,1]}}"#
    let form = try JSONDecoder().decode(FormRecord.self, from: Data(old.utf8))
    #expect(form.value("e4 e5", .w) == 1)
    #expect(form.value("e4 e5", .b) == nil)
  }

  /// Rule 5.
  @Test func endgamesFamiliesReadTheirLastFiveRounds() {
    #expect(endgameForm([true, true]) == nil)
    #expect(endgameForm([true, true, true]) == 1)
    #expect(endgameForm([false, false, true, true, true]) == 0.6)
    #expect(endgameForm([false, false, false, false, false, true, true, true, true]) == 0.8)
    var record = EndgameRecord()
    let entry = ENDGAME_LIBRARY[0]
    for success in [true, false, true, true, true, true] { record.review(entry, success: success) }
    #expect(record.results[entry.family] == [false, true, true, true, true])
    #expect(record.form(entry.family) == 0.8)
  }
}
