import Foundation
import Model
import Testing

/// The run's constants against Golden/constants.json: Survival, missions,
/// Autopilot, recommend, freshness, the draw, holes, lenses.
@Test func runConstants() throws {
  let all = try JSON.parse(Data(contentsOf: Cases.golden.appendingPathComponent("constants.json")))
  func expect(_ file: String, _ name: String, _ value: JSONable, sourceLocation: SourceLocation = #_sourceLocation) {
    let want = all["src/model/\(file).ts"][name]
    #expect(want != .null, "\(file).\(name) is not in constants.json", sourceLocation: sourceLocation)
    #expect(matches(value.json, want), "\(file).\(name): \(value.json) is not \(want)", sourceLocation: sourceLocation)
  }
  let s = "survival"
  expect(s, "BOOK_SHARE", BOOK_SHARE)
  expect(s, "COMBO_CLEAN", COMBO_CLEAN)
  expect(s, "COMBO_HOLD", COMBO_HOLD)
  expect(s, "CONVERT_FROM", CONVERT_FROM)
  expect(s, "CONVERT_WINDOW", CONVERT_WINDOW)
  expect(s, "DEFAULT_SURVIVAL", webEncoded(DEFAULT_SURVIVAL))
  expect(s, "EDGE_MOVES", EDGE_MOVES)
  expect(s, "EMPTY_SURVIVAL_SCORE", encoded(SurvivalScore()))
  expect(s, "HISTORY_RUNS", HISTORY_RUNS)
  expect(s, "MISSION_BONUS", MISSION_BONUS)
  expect(s, "MISSION_BREAK", MISSION_BREAK)
  expect(s, "MISSION_DUG", MISSION_DUG)
  expect(s, "MISSION_LEAD", MISSION_LEAD)
  expect(s, "MISSION_WINDOW", MISSION_WINDOW)
  expect(s, "MOMENT_BONUS", MOMENT_BONUS)
  expect(s, "MOMENT_FLOOR", MOMENT_FLOOR)
  expect(s, "MOMENT_FOUND", MOMENT_FOUND)
  expect(s, "MOMENT_GAP", MOMENT_GAP)
  expect(s, "MOMENT_STREAK_BONUS", MOMENT_STREAK_BONUS)
  expect(s, "NO_EXTRAS", encoded(NO_EXTRAS))
  expect(s, "PLAN_SLACK", PLAN_SLACK)
  expect(s, "PLAN_WINDOW", PLAN_WINDOW)
  expect(s, "RECENT_RUNS", RECENT_RUNS)
  expect(s, "SCORE_SLIGHT", SCORE_SLIGHT)

  expect("autopilot", "LEAN_FOR", Dictionary(uniqueKeysWithValues: LEAN_FOR.map { ($0.key.rawValue, $0.value.rawValue) }))

  let r = "recommend"
  expect(r, "ACCURACY_RUNS", ACCURACY_RUNS)
  expect(r, "BRAKE", BRAKE)
  expect(r, "BRAKE_WINDOW", BRAKE_WINDOW)
  expect(r, "DEPTH", DEPTH)
  expect(r, "STALENESS", STALENESS)
  expect(r, "STEER_GAP", STEER_GAP)
  expect(r, "TEST_FLOOR", TEST_FLOOR)

  expect("freshness", "HEAD_WEIGHT", HEAD_WEIGHT)
  expect("freshness", "NOTHING_SEEN", obj(["at": [String: Int]().mapValues { $0 }, "round": NOTHING_SEEN.round]))
  expect("evalDelta", "EVEN_CP", EVEN_CP)
  expect("autopilotPrefs", "AUTO_GROWTH", encoded(AUTO_GROWTH))
  expect("autopilotPrefs", "DEFAULT_AUTOPILOT", encoded(DEFAULT_AUTOPILOT))
  // DEFAULT_PLAY differs on purpose: levels are ratings now (PlayTests).
  var play = DEFAULT_PLAY
  play.level = "club"
  expect("modes", "DEFAULT_PLAY", encoded(play))
  #expect(levelById(DEFAULT_PLAY.level) == levelById("club"))
  expect("openingRun", "CLOCK_MODES", CLOCK_MODES.map(\.rawValue))
  expect("openingRun", "DRAW_WINDOW", DRAW_WINDOW)
  expect("growth", "DEFAULT_MAX_PLY", DEFAULT_MAX_PLY)
  expect("growth", "DEFAULT_MIN_SHARE", DEFAULT_MIN_SHARE)
  expect("growth", "MAX_ADDS", MAX_ADDS)
  expect("boardHints", "KING_GRADE_TEXT", Dictionary(uniqueKeysWithValues: KING_GRADE_TEXT.map { ($0.key.rawValue, $0.value) }))
  expect("boardHints", "LENSES", JSON.array(LENSES.map { obj(["kind": $0.kind.rawValue, "label": $0.label]) }))
}
