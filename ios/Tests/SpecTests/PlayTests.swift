import ChessCore
import Foundation
import Model
import Testing

/// Golden/cases/functions/play.json, built as `play.cases.ts` builds them.
@Test func play() throws {
  let at = ISO8601DateFormatter().date(from: "2026-10-01T12:00:00Z")!.timeIntervalSince1970 * 1000
  let long = "e4 e5 Nf3 Nc6 Bb5 a6 Ba4 Nf6 O-O Be7 Re1 b5 Bb3 d6 c3 O-O h3 Nb8 d4 Nbd7 c4 c6 cxb5 axb5 Nc3 Bb7 Bg5 b4 Nb1 h6 Bh4 c5 dxe5 Nxe5 Nxe5 dxe5 Qxd8 Rfxd8 Nd2 Bd6 f3"
    .split(separator: " ").map(String.init)

  /// Candidate lines, best first, as the engine reports them.
  func lines(_ n: Int) -> [EngineLine] {
    n < 1 ? [] : (1...n).map { EngineLine(multipv: $0, depth: 5, cp: Double(40 - $0 * 10), mate: nil, pv: ["m\($0)", "x"]) }
  }
  func game(_ id: String, _ source: String, _ date: String) -> ImportedGame {
    ImportedGame(
      id: id, source: ImportedGame.Source(rawValue: source)!, white: "a", black: "b", result: "1-0",
      userColor: .w, date: date, moves: ["e4", "e5"])
  }
  func ids(_ games: [ImportedGame]) -> JSON { games.map { "\($0.id):\($0.source.rawValue)" }.json }
  func color(_ j: JSON) -> Color { Color(rawValue: j.string)! }

  // Levels, move choice and the engine's name on a game no longer match the
  // web: levels are ratings now. Their own tests are below.
  try check("play", [
    "play.openingLine": { a in openingLine(Array(long.prefix(a[0].int)), color(a[1])).joined(separator: " ").json },
    "play.playedGame": { a in
      let played = playedGame(
        id: "play_1", color: color(a[1]), moves: Array(long.prefix(a[2].int)),
        result: GameResult(rawValue: a[0].string)!, level: levelById("strong"), at: at)
      return played.map(encoded) ?? .null
    },
    "play.withPlayGame": { a in
      let before = a[0].array.map { game($0[0].string, $0[1].string, "2026-10-01") }
      return ids(withPlayGame(before, game(a[1].string, "play", "2026-10-02")))
    },
    "play.withPlayGame (cap)": { a in
      var games = [game("l1", "lichess", "2026-01-01")]
      for i in 1...a[0].int { games = withPlayGame(games, game("p\(i)", "play", "2026-10-01")) }
      return obj(["kept": games.count, "first": games[0].id, "last": ids(Array(games.suffix(2)))])
    },
    "play.mergeGames": { a in
      func games(_ j: JSON) -> [ImportedGame] { j.array.map { game($0[0].string, $0[1].string, $0[2].string) } }
      return ids(mergeGames(games(a[0]), games(a[1])))
    },
  ], only: ["play.openingLine", "play.withPlayGame", "play.withPlayGame (cap)", "play.mergeGames"])
}

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
  #expect(LEVELS.map(\.name) == ["800", "1200", "1600", "2000"])
  #expect(levelById("1600").rating == 1600)
  // Saves from before keep a matching strength.
  #expect(levelById("club").rating == 1200)
  #expect(levelById("full").rating == 2000)
  #expect(levelById("nonsense").rating == 1200)
  // Stronger looks further and gives up less.
  for (weaker, stronger) in zip(LEVELS, LEVELS.dropFirst()) {
    #expect(weaker.depth <= stronger.depth)
    #expect(weaker.temperature > stronger.temperature)
    #expect(weaker.window > stronger.window)
  }
  #expect(levelFor(rating: 100).rating == MIN_RATING)
  #expect(levelFor(rating: 1400).depth == 4)
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
  for level in [levelFor(rating: MIN_RATING)] + LEVELS {
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

@Test func playedGameNamesTheRating() {
  let game = playedGame(id: "g", color: .w, moves: ["e4", "e5"], result: .win, level: levelById("1600"), at: 0)
  #expect(game?.black == "Engine (1600)")
}
