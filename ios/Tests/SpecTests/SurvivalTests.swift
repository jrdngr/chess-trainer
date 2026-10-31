import ChessCore
import Foundation
import Model
import Testing

func color(_ j: JSON) -> Color { Color(rawValue: j.string)! }

/// spec/cases/functions/survival.json
@Test func survival() throws {
  let tree = openingTree(bookIndex)
  func record(_ runs: [JSON], _ opening: String) -> JSON {
    var rec = SurvivalRecord()
    return .array(runs.map { run in
      let l = line(run["line"].string)
      if run.object["ended"] != nil {
        rec = recordEndedSurvival(rec, tree, l)
      } else {
        rec = recordSurvival(rec, tree, l, run["moves"].int, run["points"].numberOrNil.map(Int.init))
      }
      return obj(["global": encoded(rec.global), "opening": encoded(survivalFor(rec, opening)), "form": recentForm(rec.global)])
    })
  }
  try check("survival", [
    "survival.moveScore": { a in moveScore(a[0].number).map { obj(["cp": $0.cp, "tone": $0.tone.rawValue]) } ?? .null },
    "survival.evalSwing": { evalSwing(color($0[0]), $0[1].number, $0[2].number).json },
    "survival.glowFor": { a in glowFor(color(a[0]), a[1].number).map(encoded) ?? .null },
    "survival.speedTone": { speedTone($0[0].number).rawValue.json },
    "survival.secondsText": { secondsText($0[0].number).json },
    "survival.prepSummary": { prepSummary($0[0].int, $0[1].int, $0[2].numbers, $0[3].int).json },
    "survival.comboAfter": { comboAfter($0[0].int, $0[1].number).json },
    "survival.comboMultiplier": { comboMultiplier($0[0].int).json },
    "survival.isMoment": { isMoment(color($0[0]), $0[1].number, $0[2].numberOrNil).json },
    "survival.momentBonus": { momentBonus($0[0].int).json },
    "survival.missionTitle": { missionTitle(MissionKind(rawValue: $0[0].string)!).json },
    "survival.moveNumber": { moveNumber($0[0].int).json },
    "survival.survivalSteerLabel": { survivalSteerLabel(SurvivalSteer(rawValue: $0[0].string)!).json },
    "survival.openingsAlong": { openingsAlong(tree, line($0[0].string)).json },
    "survival.recordSurvival (runs)": { record($0[0].array, $0[1].string) },
    "survival.recentForm": { a in
      var score = SurvivalScore()
      score.recent = a[0].numbers.map(Int.init)
      return recentForm(score).json
    },
    "survival.normalizeSurvival": { a in encoded(a[0] == .null ? SurvivalRecord() : a[0].decoded(SurvivalRecord.self)) },
    "survival.DEFAULT_SURVIVAL": { _ in encoded(DEFAULT_SURVIVAL) },
  ])
}
