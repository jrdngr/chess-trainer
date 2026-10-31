import ChessCore
import Foundation

/// Reading PGN: `parsePgn` and `mainline` in `src/chess/pgn.ts`.

/// A move in a game's tree. `children.nodes[0]` is the main continuation; the rest are variations of it.
public final class PgnNode {
  public let san: String
  public var comment: String?
  public var nags: [String] = []
  public let children = PgnList()
  init(san: String) { self.san = san }
}

/// A list of moves that a parse appends to, shared like the prototype's arrays.
public final class PgnList {
  public var nodes: [PgnNode] = []
}

public struct PgnGame {
  public var headers: [String: String]
  /// First moves of the game; [0] is the mainline.
  public var moves: [PgnNode]
  public var result: String
}

private let RESULTS: Set<String> = ["1-0", "0-1", "1/2-1/2", "*"]

private enum Token {
  case move(String), open, close, comment(String), nag(String), result(String)
}

private func tokenize(_ text: String) -> [Token] {
  let chars = Array(text)
  var tokens: [Token] = []
  var i = 0
  func upTo(_ stop: Character, from: Int) -> Int { chars[from...].firstIndex(of: stop) ?? chars.count }
  while i < chars.count {
    let ch = chars[i]
    if ch.isWhitespace {
      i += 1
    } else if ch == "{" || ch == ";" {
      let stop = upTo(ch == "{" ? "}" : "\n", from: i)
      tokens.append(.comment(String(chars[(i + 1)..<stop]).trimmingCharacters(in: .whitespacesAndNewlines)))
      i = stop + 1
    } else if ch == "(" {
      tokens.append(.open)
      i += 1
    } else if ch == ")" {
      tokens.append(.close)
      i += 1
    } else if ch == "$" {
      var j = i + 1
      while j < chars.count, chars[j].isASCII, chars[j].isNumber { j += 1 }
      tokens.append(.nag(String(chars[i..<j])))
      i = j
    } else if ch == "<" || ch == ">" {
      i += 1
    } else {
      var j = i
      while j < chars.count, !chars[j].isWhitespace, !"{}()<>;".contains(chars[j]) { j += 1 }
      let word = String(chars[i..<j])
      i = j
      if RESULTS.contains(word) {
        tokens.append(.result(word))
      } else {
        // Strip move numbers and dots: "12." "12..." "12.Nf3" are all valid.
        let san = word.replacing(/^\d+\.*/, with: "").replacing(/^\.+/, with: "")
        if !san.isEmpty, san.wholeMatch(of: /\d+/) == nil {
          // Drop decorations chess.js does not need.
          tokens.append(.move(san.replacing(/[?!]+$/, with: "")))
        }
      }
    }
  }
  return tokens
}

/// A `( ... )` group is an alternative to the move before it, so its moves join that move's siblings.
private func parseMoves(_ tokens: [Token], _ start: Int, _ out: PgnList) -> (end: Int, result: String) {
  var siblings = out
  var last: PgnNode?
  var prevSiblings = out
  var result = "*"
  var i = start
  while i < tokens.count {
    switch tokens[i] {
    case .close: return (i + 1, result)
    case .result(let value):
      result = value
      i += 1
    case .move(let san):
      let node = PgnNode(san: san)
      siblings.nodes.append(node)
      prevSiblings = siblings
      last = node
      siblings = node.children
      i += 1
    case .comment(let text):
      if let last { last.comment = last.comment.map { "\($0) \(text)" } ?? text }
      i += 1
    case .nag(let value):
      last?.nags.append(value)
      i += 1
    case .open:
      let inner = PgnList()
      i = parseMoves(tokens, i + 1, inner).end
      prevSiblings.nodes.append(contentsOf: inner.nodes)
    }
  }
  return (i, result)
}

private func onlyHeaders(_ chunk: String) -> Bool {
  chunk.split(separator: "\n", omittingEmptySubsequences: false).allSatisfy {
    let line = $0.trimmingCharacters(in: .whitespaces)
    return line.hasPrefix("[") || line.isEmpty
  }
}

/// Every game in a PGN text.
public func parsePgn(_ pgn: String) -> [PgnGame] {
  let text = pgn.replacing(/\r\n?/, with: "\n")
  // Split on a header block that follows a blank line.
  let chunks = text.split(separator: /\n\s*\n(?=\[)/, omittingEmptySubsequences: false)
    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
    .filter { !$0.isEmpty }
  // A chunk that is only headers belongs with the chunk after it.
  var merged: [String] = []
  for chunk in chunks {
    if onlyHeaders(chunk) || merged.isEmpty || !onlyHeaders(merged[merged.count - 1]) {
      merged.append(chunk)
    } else {
      merged[merged.count - 1] += "\n\n\(chunk)"
    }
  }
  var games: [PgnGame] = []
  for chunk in merged {
    var headers: [String: String] = [:]
    var body: [Substring] = []
    for line in chunk.split(separator: "\n", omittingEmptySubsequences: false) {
      if let m = line.wholeMatch(of: /\s*\[(\w+)\s+"([^"]*)"\]\s*/) {
        headers[String(m.1)] = String(m.2)
      } else {
        body.append(line)
      }
    }
    let movetext = body.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    if movetext.isEmpty && headers.isEmpty { continue }
    let moves = PgnList()
    let (_, result) = parseMoves(tokenize(movetext), 0, moves)
    if moves.nodes.isEmpty && headers.isEmpty { continue }
    games.append(PgnGame(headers: headers, moves: moves.nodes, result: headers["Result"] ?? result))
  }
  return games
}

/// Mainline SAN moves of a parsed game, checked against the rules.
public func pgnMainline(_ game: PgnGame, _ startFen: String = START_FEN) -> [String] {
  var out: [String] = []
  var fen = game.headers["FEN"] ?? startFen
  var nodes = game.moves
  while let node = nodes.first, let move = applySan(fen, node.san) {
    out.append(move.san)
    fen = move.after
    nodes = node.children.nodes
  }
  return out
}
