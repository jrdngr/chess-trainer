import ChessCore
import Foundation
import Model
import Testing

/// spec/cases/functions/play.json, built as `play.cases.ts` builds them.
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

  try check("play", [
    "play.levelById": { levelById($0[0].string).name.json },
    "play.chooseMove": { a in chooseMove(lines(a[1].int), levelById(a[0].string), { a[2].number }).json },
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
  ])
}
