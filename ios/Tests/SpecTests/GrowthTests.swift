import ChessCore
import Foundation
import Model
import Testing

func replyJSON(_ r: Reply) -> JSON {
  obj(["san": r.san, "games": r.games, "white": r.white, "draw": r.draw, "black": r.black, "share": r.share, "next": r.next])
}

/// The growth functions in Golden/cases/functions/growth.json.
@Test func growth() throws {
  let index = bookIndex
  try check("growth", [
    "growth.holeShare": { holeShare(share: $0[0]["share"].number, kept: $0[0]["kept"].bool).json },
    "growth.movesToFit": { movesToFit($0[0].int, $0[1].int).json },
    "growth.addsToFit": { addsToFit($0[0].int, $0[1].int).json },
    "growth.optionsAt": { a in .array(optionsAt(index, a[0].string, a[1].int).map(replyJSON)) },
    "growth.choicesAt": { a in .array(choicesAt(index, a[0].string, 4).map(replyJSON)) },
  ], only: ["growth.holeShare", "growth.movesToFit", "growth.addsToFit", "growth.optionsAt", "growth.choicesAt"])
}
