import Foundation

/// Live clients for the two public game APIs.
/// Only a public username lookup is sent; nothing signs in.

public enum FetchFailure: String, Sendable {
  case notFound = "not-found", network, blocked, rateLimited = "rate-limited", empty
}

public enum FetchResult: Sendable {
  case ok([ImportedGame])
  case failed(FetchFailure, String)
}

/// One GET: the status and body. URLSession in the app; a saved response in tests.
public typealias HTTPGet = @Sendable (_ url: URL, _ accept: String?) async throws -> (status: Int, body: Data)

/// The live GET, through URLSession.
public let urlSessionGet: HTTPGet = { url, accept in
  var request = URLRequest(url: url)
  if let accept { request.setValue(accept, forHTTPHeaderField: "Accept") }
  let (data, response) = try await URLSession.shared.data(for: request)
  return ((response as? HTTPURLResponse)?.statusCode ?? 0, data)
}

/// A request that never got an answer: "blocked" (it could not reach the site), or another error.
private func classify(_ error: Error) -> FetchResult {
  if error is URLError { return .failed(.blocked, error.localizedDescription) }
  return .failed(.network, error.localizedDescription)
}

private func pathPart(_ s: String) -> String {
  s.addingPercentEncoding(withAllowedCharacters: .alphanumerics.union(CharacterSet(charactersIn: "-_.!~*'()"))) ?? s
}

public func fetchLichessGames(_ username: String, max: Int = 100, get: HTTPGet = urlSessionGet) async -> FetchResult {
  let url = URL(string: "https://lichess.org/api/games/user/\(pathPart(username))?max=\(max)&rated=true&perfType=blitz,rapid,classical&clocks=false&evals=false&opening=true")!
  do {
    let res = try await get(url, "application/x-chess-pgn")
    if res.status == 404 { return .failed(.notFound, "No Lichess account called \"\(username)\".") }
    if res.status == 429 { return .failed(.rateLimited, "Lichess is rate limiting; try again in a minute.") }
    if !(200..<300).contains(res.status) { return .failed(.network, "Lichess returned \(res.status).") }
    let games = gamesFromPgn(String(decoding: res.body, as: UTF8.self), username, .lichess)
    return games.isEmpty ? .failed(.empty, "No rated games found for that account.") : .ok(games)
  } catch {
    return classify(error)
  }
}

private struct Archives: Decodable { var archives: [String] }
private struct Month: Decodable {
  struct Game: Decodable {
    var pgn: String?
    var url: String?
    var rules: String?
  }
  var games: [Game]?
}

public func fetchChesscomGames(_ username: String, max: Int = 100, get: HTTPGet = urlSessionGet) async -> FetchResult {
  let user = pathPart(username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
  do {
    let res = try await get(URL(string: "https://api.chess.com/pub/player/\(user)/games/archives")!, nil)
    if res.status == 404 { return .failed(.notFound, "No Chess.com account called \"\(username)\".") }
    if !(200..<300).contains(res.status) { return .failed(.network, "Chess.com returned \(res.status).") }
    let archives = try JSONDecoder().decode(Archives.self, from: res.body).archives
    var games: [ImportedGame] = []
    // Newest months first, until we have enough games.
    for archive in archives.reversed() {
      if games.count >= max { break }
      guard let url = URL(string: archive) else { continue }
      let month = try await get(url, nil)
      if !(200..<300).contains(month.status) { continue }
      for g in try JSONDecoder().decode(Month.self, from: month.body).games ?? [] {
        guard let pgn = g.pgn, g.rules == nil || g.rules == "chess" else { continue }
        for var p in gamesFromPgn(pgn, username, .chesscom) {
          p.url = g.url ?? p.url
          games.append(p)
        }
      }
    }
    return games.isEmpty ? .failed(.empty, "No games found for that account.") : .ok(Array(games.prefix(max)))
  } catch {
    return classify(error)
  }
}

public func fetchGames(_ site: GameSite, _ username: String, max: Int = 100, get: HTTPGet = urlSessionGet) async -> FetchResult {
  site == .lichess ? await fetchLichessGames(username, max: max, get: get) : await fetchChesscomGames(username, max: max, get: get)
}
