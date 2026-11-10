import ChessCore
import Foundation

/// Stockfish's verdict on every legal move from each book position, worked
/// out offline (depth 12) and shipped as data. Each line of `BookScores.txt`
/// is `position key|best|uci:lost,uci:lost,...`: the best move's score for the
/// side to move and what each move gives up against it, in centipawns.
public enum BookScores {
  struct Entry: Sendable {
    let best: Int
    let lost: [Substring: Int]
  }

  static let table: [String: Entry] = {
    guard let url = Bundle.module.url(forResource: "BookScores", withExtension: "txt"),
      let text = try? String(contentsOf: url, encoding: .utf8)
    else { return [:] }
    var out: [String: Entry] = [:]
    for line in text.split(separator: "\n") {
      let fields = line.split(separator: "|", omittingEmptySubsequences: false)
      guard fields.count == 3, let best = Int(fields[1]) else { continue }
      var lost: [Substring: Int] = [:]
      for move in fields[2].split(separator: ",") {
        let parts = move.split(separator: ":")
        if parts.count == 2, let cp = Int(parts[1]) { lost[parts[0]] = cp }
      }
      out[String(fields[0])] = Entry(best: best, lost: lost)
    }
    return out
  }()

  /// The best score and what `uci` gives up, for the side to move, when the position is in the table.
  public static func score(_ fen: String, _ uci: String) -> (best: Int, lost: Int)? {
    guard let entry = table[positionKey(fen)], let lost = entry.lost[Substring(uci)] else { return nil }
    return (entry.best, lost)
  }
}
