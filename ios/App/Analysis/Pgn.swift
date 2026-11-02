import ChessCore
import Foundation

/// What Analysis needs of PGN: the first game's mainline, read
/// from pasted PGN, and a line written back out.
enum Pgn {
  private static let results: Set<String> = ["1-0", "0-1", "1/2-1/2", "*"]

  /// The first game's mainline SAN, checked against the rules; nil when the text holds no game,
  /// or a game set up from a position other than the start, which Analysis cannot show.
  static func mainline(_ pgn: String) -> [String]? {
    let text = pgn.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
    var fenHeader: String?
    var body: [Substring] = []
    var sawGame = false
    for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
      if let m = line.wholeMatch(of: /\s*\[(\w+)\s+"([^"]*)"\]\s*/) {
        // A header after movetext starts the next game.
        if !body.joined().trimmingCharacters(in: .whitespaces).isEmpty { break }
        sawGame = true
        if m.1 == "FEN" { fenHeader = String(m.2) }
      } else {
        body.append(line)
      }
    }
    let sans = firstLine(body.joined(separator: "\n"))
    if sans.isEmpty && !sawGame { return nil }
    // Analysis walks every line from the start position.
    if let fenHeader, positionKey(fenHeader) != positionKey(START_FEN) { return nil }
    var fen = START_FEN
    var out: [String] = []
    for san in sans {
      guard let move = applySan(fen, san) else { break }
      out.append(move.san)
      fen = move.after
    }
    return out
  }

  /// The movetext's first moves at the top level: variations, comments and NAGs skipped.
  private static func firstLine(_ text: String) -> [String] {
    var out: [String] = []
    var depth = 0
    let chars = Array(text)
    var i = 0
    while i < chars.count {
      let ch = chars[i]
      if ch.isWhitespace || ch == "<" || ch == ">" {
        i += 1
      } else if ch == "{" {
        i = chars[i...].firstIndex(of: "}").map { $0 + 1 } ?? chars.count
      } else if ch == ";" {
        i = chars[i...].firstIndex(of: "\n").map { $0 + 1 } ?? chars.count
      } else if ch == "(" {
        depth += 1
        i += 1
      } else if ch == ")" {
        depth = max(0, depth - 1)
        i += 1
      } else if ch == "$" {
        i += 1
        while i < chars.count, chars[i].isNumber { i += 1 }
      } else {
        var j = i
        while j < chars.count, !chars[j].isWhitespace, !"{}()<>;".contains(chars[j]) { j += 1 }
        let word = String(chars[i..<j])
        i = j
        guard depth == 0, !results.contains(word) else { continue }
        // "12." "12..." "12.Nf3" are all move numbers in front of a move; a number
        // needs its dot, so "0-0" stays castling. A lone "!?" is no move.
        let san = word.replacing(/^\d+\.+/, with: "").replacing(/^\.+/, with: "").replacing(/[?!]+$/, with: "")
        guard !san.isEmpty, san.wholeMatch(of: /\d+/) == nil else { continue }
        out.append(san)
      }
    }
    return out
  }

  /// A line as a PGN game, wrapped at 80: `toPgn` then `wrapPgn`.
  static func export(_ sans: [String], date: Date = Date()) -> String {
    let day = date.formatted(.iso8601.year().month().day()).replacingOccurrences(of: "-", with: ".")
    let head = "[Event \"Analysis\"]\n[Result \"*\"]\n[Date \"\(day)\"]"
    let pgn = "\(head)\n\n\(sansToMoveText(sans)) *\n"
    return wrap(pgn)
  }

  /// `wrapPgn`: words joined into lines no longer than `width`.
  static func wrap(_ text: String, width: Int = 80) -> String {
    var lines: [String] = []
    var line = ""
    for w in text.split(separator: " ", omittingEmptySubsequences: false).map(String.init) {
      if line.count + w.count + 1 > width {
        lines.append(line)
        line = w
      } else {
        line = line.isEmpty ? w : "\(line) \(w)"
      }
    }
    if !line.isEmpty { lines.append(line) }
    return lines.joined(separator: "\n")
  }
}
