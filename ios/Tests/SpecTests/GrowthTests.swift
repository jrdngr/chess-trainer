import ChessCore
import Foundation
import Model
import Testing

func holeJSON(_ h: Hole) -> JSON {
  obj(["path": h.path, "fen": h.fen, "san": h.san, "share": h.share, "games": h.games, "after": h.after,
       "kept": h.kept ? true : nil, "reach": h.reach])
}

func replyJSON(_ r: Reply) -> JSON {
  obj(["san": r.san, "games": r.games, "white": r.white, "draw": r.draw, "black": r.black, "share": r.share, "next": r.next])
}

func rowJSON(_ r: GrowthRow) -> JSON {
  obj([
    "id": r.id, "playbookId": r.playbookId, "color": r.color.rawValue, "name": r.name, "eco": r.eco, "depth": r.depth,
    "topShare": r.topShare, "urgency": r.urgency, "score": r.score,
    "holes": JSON.array(r.holes.map(holeJSON)),
    "ends": JSON.array(r.ends.map { obj(["path": $0.path, "fen": $0.fen, "reach": $0.reach]) }),
  ])
}

/// The growth functions in Golden/cases/functions/growth.json.
@Test func growth() throws {
  let index = bookIndex
  func options(_ j: JSON) -> GrowthOptions {
    GrowthOptions(minShare: j["minShare"].numberOrNil, maxPly: j["maxPly"].numberOrNil.map(Int.init))
  }
  try check("growth", [
    "growth.holeShare": { holeShare(share: $0[0]["share"].number, kept: $0[0]["kept"].bool).json },
    "growth.movesToFit": { movesToFit($0[0].int, $0[1].int).json },
    "growth.addsToFit": { addsToFit($0[0].int, $0[1].int).json },
    "growth.rowUrgency": { rowUrgency($0[0].int, $0[1].number, $0[2].int).json },
    "growth.optionsAt": { a in .array(optionsAt(index, a[0].string, a[1].int).map(replyJSON)) },
    "growth.choicesAt": { a in .array(choicesAt(index, a[0].string, 4).map(replyJSON)) },
    "growth.pastTheBook": { pastTheBook(index, $0[0].string).json },
    "growth.growthRows": { a in .array(growthRows([rep(a[0])], index, options(a[1])).map(rowJSON)) },
  ], only: ["growth.holeShare", "growth.movesToFit", "growth.addsToFit", "growth.rowUrgency", "growth.optionsAt", "growth.choicesAt", "growth.pastTheBook", "growth.growthRows"])
}

/// A one-line Ruy Lopez grows its earliest reply first, though forks deep in
/// the main line are met more often than the third-move sidelines.
@Test func growthStartsAtTheShallowestReply() {
  let tree = openingTree(bookIndex)
  let main = "e4 e5 Nf3 Nc6 Bb5 a6 Ba4 Nf6 O-O Be7 Re1 b5 Bb3 d6 c3 O-O h3"
  let opening = deepestNodeWithin(tree, tree.root, line("e4 e5 Nf3 Nc6 Bb5"))
  let launch = growLaunch(rep(.w, [main]), bookIndex, tree, opening, minShare: 1, maxPly: 18)
  let hole = launch.flatMap { firstHole($0.row) }
  #expect(hole?.path == line("e4 e5 Nf3 Nc6 Bb5"))
  #expect(hole?.san == "Nf6")
}

/// With only 1.e4 kept and the Smith-Morra chosen, the work Growth finds is
/// 1...c5 on the way in, none of it inside: the lobby's Start keeps the opening.
@Test func wayInWorkIsNotInsideTheOpening() {
  let tree = openingTree(bookIndex)
  let morra = tree.byId["e4 c5 d4"]!
  let rows = growthRows([rep(.w, ["e4"])], bookIndex, GrowthOptions(minShare: 1, maxPly: 18, region: (tree, morra)))
  #expect(rows.first?.holes.contains { $0.path == ["e4"] && $0.san == "c5" } == true)
  #expect(!rows.contains { rowReaches(tree, morra, $0) })
}

/// A sitting's moves stay off the tree it started from until Save Line,
/// which writes the kept opening line and every answer still standing.
@Test func growthDraftSavesOnlyWhatIsLeft() {
  var draft = GrowthDraft(rep(.w, ["e4"]), keep: line("e4 c5 d4 cxd4 c3"))
  draft.add(line("e4 c5 d4 cxd4 c3 dxc3 Nxc3"), .fixed(.growth))
  draft.add(line("e4 c5 d4 cxd4 c3 Nf6 e5"), .fixed(.growth))
  draft.remove(nodeAtLine(draft.rep, line("e4 c5 d4 cxd4 c3 Nf6"))!.id)
  var state = AppState()
  let id = state.ensurePlaybook(.w)
  state.saveGrowth(id, draft)
  let saved = state.playbooks[id]!
  #expect(leafLines(saved).map { $0.sans.joined(separator: " ") } == ["e4 c5 d4 cxd4 c3 dxc3 Nxc3"])
  #expect(nodeAtLine(saved, line("e4 c5 d4 cxd4 c3"))?.source == .picker)
}
