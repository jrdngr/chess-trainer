import ChessCore
import Foundation
import Model
import Testing

/// Candidate lines best first, from White's side, each costing what's given.
private func candidates(_ losses: [Double]) -> [EngineLine] {
  losses.enumerated().map { i, loss in EngineLine(multipv: i + 1, depth: 5, cp: 50 - loss, mate: nil, pv: ["m\(i + 1)"]) }
}

/// How often each candidate is picked over many draws.
private func picks(_ lines: [EngineLine], _ level: Level) -> [String: Int] {
  let rand = mulberry32(seed: 7)
  var counts: [String: Int] = [:]
  for _ in 0..<4000 { counts[chooseMove(lines, level, rand)!, default: 0] += 1 }
  return counts
}

@Test func levelsAreRatings() {
  #expect(LEVEL_RATINGS.map(levelFor(rating:)).map(\.name) == ["800", "1200", "1600", "2000"])
  #expect(levelById("1600").rating == 1600)
  // Saves from before keep a matching strength.
  #expect(levelById("club").rating == 1200)
  #expect(levelById("full").rating == 2000)
  #expect(levelById("nonsense").rating == 1200)
  // Stronger looks further and gives up less.
  for (weaker, stronger) in zip(LEVEL_RATINGS.map(levelFor(rating:)), LEVEL_RATINGS.map(levelFor(rating:)).dropFirst()) {
    #expect(weaker.depth <= stronger.depth)
    #expect(weaker.temperature > stronger.temperature)
    #expect(weaker.window > stronger.window)
  }
  #expect(levelFor(rating: 100).rating == MIN_RATING)
  #expect(levelFor(rating: 1400).depth == 3)
}

@Test func slipsAreSmallMoreOftenThanBig() {
  // Best, a 10cp slip, a 50cp one.
  let lines = candidates([0, 10, 50])
  let weak = picks(lines, levelFor(rating: 800)), strong = picks(lines, levelFor(rating: 1600))
  #expect(weak["m2", default: 0] > weak["m3", default: 0])
  #expect(weak["m3", default: 0] > 0)
  #expect(strong["m1", default: 0] > weak["m1", default: 0])
}

@Test func aSeenBlunderIsNeverPlayed() {
  // One move keeps the piece; eleven drop it (9...Rb8 instead of 9...Nxf5).
  let lines = candidates([0] + Array(repeating: 300, count: 11))
  for level in [levelFor(rating: MIN_RATING)] + LEVEL_RATINGS.map(levelFor(rating:)) {
    #expect(picks(lines, level)["m1", default: 0] == 4000)
  }
}

@Test func aLossPastTheWindowIsNeverPlayed() {
  let level = levelFor(rating: 1200)
  let counts = picks(candidates([0, level.window - 5, level.window + 5]), level)
  #expect(counts["m2", default: 0] > 0)
  #expect(counts["m3", default: 0] == 0)
}

@Test func equalMovesAreEquallyLikely() {
  let counts = picks(candidates([0, 0]), levelFor(rating: 2000))
  #expect(abs(counts["m1", default: 0] - counts["m2", default: 0]) < 300)
}

@Test func mateIsNotPassedUpLightly() {
  let lines = [
    EngineLine(multipv: 1, depth: 5, cp: nil, mate: 1, pv: ["mate"]),
    EngineLine(multipv: 2, depth: 5, cp: 300, mate: nil, pv: ["piece"]),
  ]
  #expect(picks(lines, levelFor(rating: 800))["mate", default: 0] == 4000)
}

