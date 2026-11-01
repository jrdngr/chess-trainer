import Foundation
import Model
import Testing

/// The real Lichess and Chess.com APIs, with well-known public accounts.
/// Off unless `LIVE_IMPORT=1`, so the suite never needs the network.
@Test(.enabled(if: ProcessInfo.processInfo.environment["LIVE_IMPORT"] == "1"))
func liveImports() async throws {
  for (site, user) in [(GameSite.lichess, "DrNykterstein"), (.chesscom, "hikaru")] {
    switch await fetchGames(site, user, max: 20) {
    case .ok(let games):
      #expect(!games.isEmpty, "\(site.name): no games")
      let first = try #require(games.first)
      #expect(first.source == site.source)
      #expect(!first.moves.isEmpty)
      #expect(first.userColor != nil, "\(site.name): which side the user played")
      print("\(site.name) \(user): \(games.count) games, first \(first.white) v \(first.black), \(first.moves.count) plies, \(first.date ?? "?")")
    case .failed(let why, let message):
      Issue.record("\(site.name): \(why) \(message)")
    }
  }
}
