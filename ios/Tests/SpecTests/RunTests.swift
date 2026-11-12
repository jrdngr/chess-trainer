import ChessCore
import Foundation
import Model
import Testing

func color(_ j: JSON) -> Color { Color(rawValue: j.string)! }

/// Golden/cases/functions/run.json
@Test func run() throws {
  let tree = openingTree(bookIndex)
  func record(_ runs: [JSON], _ opening: String) -> JSON {
    var rec = RunRecord()
    return .array(runs.map { run in
      let l = line(run["line"].string)
      if run.object["ended"] != nil {
        rec = recordEndedRun(rec, tree, l)
      } else {
        rec = recordRun(rec, tree, l, run["moves"].int, run["points"].numberOrNil.map(Int.init))
      }
      return obj(["global": encoded(rec.global), "opening": encoded(runFor(rec, opening)), "form": recentForm(rec.global)])
    })
  }
  try check("run", [
    "run.moveScore": { a in moveScore(a[0].number).map { obj(["cp": $0.cp, "tone": $0.tone.rawValue]) } ?? .null },
    "run.evalSwing": { evalSwing(color($0[0]), $0[1].number, $0[2].number).json },
    "run.speedTone": { speedTone($0[0].number).rawValue.json },
    "run.secondsText": { secondsText($0[0].number).json },
    "run.comboAfter": { comboAfter($0[0].int, $0[1].number).json },
    "run.comboMultiplier": { comboMultiplier($0[0].int).json },
    "run.isMoment": { isMoment(color($0[0]), $0[1].number, $0[2].numberOrNil).json },
    "run.momentBonus": { momentBonus($0[0].int).json },
    "run.missionTitle": { missionTitle(MissionKind(rawValue: $0[0].string)!).json },
    "run.moveNumber": { moveNumber($0[0].int).json },
    "run.runSteerLabel": { runSteerLabel(RunSteer(rawValue: $0[0].string)!).json },
    "run.openingsAlong": { openingsAlong(tree, line($0[0].string)).json },
    "run.recordRun (runs)": { record($0[0].array, $0[1].string) },
    "run.recentForm": { a in
      var score = RunScore()
      score.recent = a[0].numbers.map(Int.init)
      return recentForm(score).json
    },
    "run.normalizeRun": { a in encoded(a[0] == .null ? RunRecord() : a[0].decoded(RunRecord.self)) },
    "run.DEFAULT_RUN": { _ in webEncoded(DEFAULT_RUN) },
  ])
}
