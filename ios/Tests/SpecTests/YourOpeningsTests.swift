import ChessCore
import Foundation
import Model
import Testing

/// A first-move name names nothing; a variation inside one is listed under its own name.
@Test func openingFamilySkipsFirstMoveNames() {
  #expect(openingFamily(bookIndex, "King's Pawn Game") == nil)
  #expect(openingFamily(bookIndex, "King's Knight Opening: Normal Variation") == nil)
  #expect(openingFamily(bookIndex, "Zukertort Opening: Sicilian Invitation") == nil)
  #expect(openingFamily(bookIndex, "Queen's Pawn Game: London System") == "London System")
  #expect(openingFamily(bookIndex, "Queen's Pawn Game: Colle System, Anti-Colle") == "Colle System")
  #expect(openingFamily(bookIndex, "Sicilian Defence: Najdorf Variation") == "Sicilian Defence")
}

/// Black's openings are the ones named after its first move, and a line that
/// stops at 1...e5 is no opening of its own.
@Test func yourOpeningsListFamiliesPastTheFirstMove() {
  let tree = openingTree(bookIndex)
  let black = rep(.b, ["e4 e5 Nf3 Nc6 Bc4 Bc5", "e4 e5 Nf3 Nc6 Bb5 a6", "e4 e5 Nc3"])
  let white = rep(.w, ["d4 d5 Nf3 Nf6 Bf4"])
  let mine = yourOpenings([black, white], tree, EMPTY_SCORE, now: 0)
  #expect(Set(mine.map { "\($0.side.rawValue) \($0.name)" }) == ["b Italian Game", "b Ruy Lopez", "b Vienna Game", "w London System"])
  #expect(mine.allSatisfy { $0.node.depth > 0 })
}

/// The same family played from both sides is two openings.
@Test func yourOpeningsKeepEachSide() {
  let tree = openingTree(bookIndex)
  let mine = yourOpenings([rep(.w, ["e4 c5 Nf3"]), rep(.b, ["e4 c5 Nf3 d6"])], tree, EMPTY_SCORE, now: 0)
  #expect(mine.map(\.name) == ["Sicilian Defence", "Sicilian Defence"])
  #expect(Set(mine.map(\.key)).count == 2)
}

/// A family the book reaches far more often comes first; playing the other today closes some of the gap.
@Test func yourOpeningsRankByReachThenRecency() {
  let tree = openingTree(bookIndex)
  let white = rep(.w, ["e4 c5 c3", "e4 e5 Qh5"])
  let unplayed = yourOpenings([white], tree, EMPTY_SCORE, now: 0)
  #expect(unplayed.map(\.name) == ["Sicilian Defence", "Wayward Queen Attack"])
  var score = ScoreState()
  let wayward = unplayed[1]
  var stats = NodeStats()
  stats.lastAt = 1_000
  score.nodes[wayward.node.id] = stats
  let played = yourOpenings([white], tree, score, now: 1_000)
  #expect(played.first { $0.name == "Wayward Queen Attack" }!.value == 2 * wayward.value)
}

/// A save from before Any Opening replaced Any favorite opens on Any Opening, same side.
@Test func anyFavoriteSavesOpenOnAnyOpening() throws {
  var settings = Settings()
  settings.selection = Selection(color: .b, opening: LEGACY_ANY_FAVORITE)
  let data = try JSONEncoder().encode(settings)
  let loaded = try JSONDecoder().decode(Settings.self, from: data)
  #expect(loaded.selection == Selection(color: .b, opening: ANY_OPENING))
}
