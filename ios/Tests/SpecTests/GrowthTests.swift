import ChessCore
import Foundation
import Model
import Testing

func holeJSON(_ h: Hole) -> JSON {
  obj(["path": h.path, "fen": h.fen, "san": h.san, "share": h.share, "games": h.games, "after": h.after,
       "kept": h.kept ? true : nil, "engine": h.engine ? true : nil, "reach": h.reach])
}

func replyJSON(_ r: Reply) -> JSON {
  obj(["san": r.san, "games": r.games, "white": r.white, "draw": r.draw, "black": r.black, "share": r.share, "engine": r.engine ? true : nil, "next": r.next])
}

func rowJSON(_ r: GrowthRow) -> JSON {
  obj([
    "id": r.id, "repertoireId": r.repertoireId, "color": r.color.rawValue, "name": r.name, "eco": r.eco, "depth": r.depth,
    "topShare": r.topShare, "starred": r.starred, "urgency": r.urgency, "score": r.score,
    "holes": JSON.array(r.holes.map(holeJSON)),
    "ends": JSON.array(r.ends.map { obj(["path": $0.path, "fen": $0.fen, "reach": $0.reach]) }),
  ])
}

/// The growth functions in Golden/cases/functions/growth.json.
@Test func growth() throws {
  let index = bookIndex
  func options(_ j: JSON) -> GrowthOptions {
    GrowthOptions(minShare: j["minShare"].numberOrNil, maxPly: j["maxPly"].numberOrNil.map(Int.init), starred: j.object["starred"]?.strings)
  }
  try check("growth", [
    "growth.holeShare": { holeShare(share: $0[0]["share"].number, kept: $0[0]["kept"].bool).json },
    "growth.movesToFit": { movesToFit($0[0].int, $0[1].int).json },
    "growth.addsToFit": { addsToFit($0[0].int, $0[1].int).json },
    "growth.rowUrgency": { rowUrgency($0[0].int, $0[1].number, $0[2].int).json },
    "growth.optionsAt": { a in .array(optionsAt(index, a[0].string, a[1].int).map(replyJSON)) },
    "growth.choicesAt": { a in choicesAt(index, a[0].string, 4).map { .array($0.map(replyJSON)) } ?? .string("undefined") },
    "growth.pastTheBook": { pastTheBook(index, $0[0].string).json },
    "growth.growthRows": { a in .array(growthRows([rep(a[0])], index, options(a[1])).map(rowJSON)) },
  ], only: ["growth.holeShare", "growth.movesToFit", "growth.addsToFit", "growth.rowUrgency", "growth.optionsAt", "growth.choicesAt", "growth.pastTheBook", "growth.growthRows"])
}

/// Golden/cases/functions/growOffer.json
@Test func growOffers() throws {
  let index = bookIndex
  let tree = openingTree(index)
  let added = 1_788_253_200_000.0  // 2026-09-01T09:00:00Z
  func repOf(_ end: JSON) -> Repertoire {
    var r = rep(end)
    for id in r.nodes.keys { r.nodes[id]!.addedAt = added }
    return r
  }
  func rounds(_ end: JSON) -> [RoundRecord] {
    end["lines"].strings.enumerated().flatMap { l, text in
      (0..<end["finishes"].int).map { n in
        RoundRecord(mode: .survival, openingId: end["opening"].string, color: color(end["color"]), answered: 4, correct: 4, perfect: true,
                    at: added + Double(n + 1) * 86_400_000 + Double(l), line: line(text))
      }
    }
  }
  // growOfferAt no longer matches the web: every grow starts at Growth's own
  // pick, not where the round ended. Its own tests are below.
  try check("growOffer", [
    "growOffer.readyToGrow": { a in readyToGrow(repOf(a[0]), tree, nodeById(tree, a[0]["opening"].string), rounds(a[0])).json },
    "growOffer.practiceOwed": { a in encoded(practiceOwed(repOf(a[0]), tree, nodeById(tree, a[0]["opening"].string), rounds(a[0]))) },
    "growOffer.practiceCap": { practiceCap($0[0].int).json },
    "growOffer.practiceText": { practiceText($0[0].string, $0[1].int).json },
    "growOffer.offerOpening": { a in
      offerOpening(tree, nodeById(tree, a[0].string), a[1].stringOrNil.map { nodeById(tree, $0) }, line(a[2].string)).id.json
    },
  ], only: ["growOffer.readyToGrow", "growOffer.practiceOwed", "growOffer.practiceCap", "growOffer.practiceText", "growOffer.offerOpening"])
}

/// A one-line opening widens before it lengthens: a clean run to the end of
/// its only line grows a common early reply it does not answer.
@Test func lineGrowWidensFirst() {
  let tree = openingTree(bookIndex)
  let played = line("d4 d5 c4 e6 Nc3")
  let opening = deepestNodeWithin(tree, tree.root, Array(played.prefix(3)))
  let offer = growOfferAt(
    rep: rep(.w, ["d4 d5 c4 e6 Nc3"]), index: bookIndex, tree: tree, opening: opening, played: played,
    rounds: [], minShare: 1, maxPly: 18, starred: [])
  #expect(offer?.kind == "line")
  #expect(offer?.onLine == false)
  let hole = offer.flatMap { firstHole($0.launch.row) }
  #expect(hole?.path == line("d4 d5 c4"))
  #expect(["c6", "dxc4"].contains(hole?.san ?? ""))
}

/// Where Growth's pick is the reply the round ended on, the button says this line.
@Test func lineGrowOnTheLinePlayed() {
  let tree = openingTree(bookIndex)
  let played = line("d4 d5 c4 c6")
  let opening = deepestNodeWithin(tree, tree.root, Array(played.prefix(3)))
  let r = rep(.w, ["d4 d5 c4 e6 Nc3", "d4 d5 c4 dxc4 e3", "d4 d5 c4 Nf6 cxd5", "d4 d5 c4 Bf5 Nc3"])
  let offer = growOfferAt(rep: r, index: bookIndex, tree: tree, opening: opening, played: played, rounds: [], minShare: 1, maxPly: 18, starred: [])
  #expect(offer?.kind == "line")
  #expect(offer?.onLine == true)
}
