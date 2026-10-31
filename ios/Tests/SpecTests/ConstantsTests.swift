import Foundation
import Model
import Testing

/// The ported modules' constants against spec/constants.json, which is
/// extracted from the prototype's TypeScript, so none of them drifts quietly.
@Test func constants() throws {
  let all = try JSON.parse(Data(contentsOf: Cases.root.appendingPathComponent("spec/constants.json")))
  func expect(_ file: String, _ name: String, _ value: JSON, sourceLocation: SourceLocation = #_sourceLocation) {
    let want = all["src/model/\(file).ts"][name]
    #expect(want != .null, "\(file).\(name) is not in constants.json", sourceLocation: sourceLocation)
    #expect(matches(value, want), "\(file).\(name): \(value) is not \(want)", sourceLocation: sourceLocation)
  }

  let srs = DEFAULT_SRS
  expect("srs", "DAY", DAY.json)
  expect("srs", "MINUTE", MINUTE.json)
  expect("srs", "RUNS_PER_DAY", RUNS_PER_DAY.json)
  expect("srs", "DEFAULT_SRS", obj([
    "learningSteps": srs.learningSteps, "relearningSteps": srs.relearningSteps,
    "graduatingInterval": srs.graduatingInterval, "easyInterval": srs.easyInterval,
    "startingEase": srs.startingEase, "minEase": srs.minEase,
    "easeDelta": Dictionary(uniqueKeysWithValues: srs.easeDelta.map { ($0.key.rawValue, $0.value) }),
    "hardMultiplier": srs.hardMultiplier, "easyBonus": srs.easyBonus,
    "lapseMultiplier": srs.lapseMultiplier, "maxInterval": srs.maxInterval,
  ]))
  expect("autopilot", "RUNS_PER_DAY", RUNS_PER_DAY.json)

  expect("scoring", "ACTIVITY_MODES", ACTIVITY_MODES.map(\.rawValue).json)
  expect("scoring", "EMPTY_SCORE", encoded(EMPTY_SCORE))
  expect("scoring", "NEW_LABEL", NEW_LABEL.json)
  expect("scoring", "RATING", obj(["start": RATING.start, "floor": RATING.floor, "step": RATING.step, "scale": RATING.scale]))
  expect("scoring", "TIERS", encoded(TIERS))
  expect("scoring", "UNRATED", encoded(UNRATED))

  expect("prepFloor", "MAX_LIFTED", MAX_LIFTED.json)
  expect("prepFloor", "PREPARED_FLOOR", PREPARED_FLOOR.json)
  expect("mistakes", "MISTAKE_LIMIT", MISTAKE_LIMIT.json)
  expect("moveSource", "SOURCE_LABELS", Dictionary(uniqueKeysWithValues: SOURCE_LABELS.map { ($0.key.rawValue, $0.value) }).json)
  expect("anyFavorite", "ANY_FAVORITE", ANY_FAVORITE.json)
  expect("openingTree", "ANY_OPENING", ANY_OPENING.json)
  expect("selection", "DEFAULT_SELECTION", encoded(DEFAULT_SELECTION))
  expect("onboarding", "NAMED_LATE", NAMED_LATE.mapValues(\.rawValue).json)
  expect("freshness", "HORIZON", HORIZON.json)
  expect("openingRun", "BLUNDER_LIMIT", BLUNDER_LIMIT.json)
  expect("openingRun", "BOOK_SHARE", BOOK_SHARE.json)
  expect("survival", "BOOK_SHARE", BOOK_SHARE.json)

  expect("pickerData", "FAMILY_SHARPNESS", FAMILY_SHARPNESS.json)
  expect("pickerData", "SHARPNESS_OVERRIDES", SHARPNESS_OVERRIDES.json)
  expect("pickerData", "BRANCH_SIDES", BRANCH_SIDES.mapValues(\.rawValue).json)
  expect("pickerData", "FAMILY_GROUPS", FAMILY_GROUPS.mapValues { split in
    obj([
      "groups": JSON.array(split.groups.map { obj(["label": $0.label, "from": $0.from, "sharpness": $0.sharpness]) }),
      "rest": split.rest, "restSharpness": split.restSharpness,
    ])
  }.json)
}
