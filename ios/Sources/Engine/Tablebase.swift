import ChessCore
import Fathom
import Foundation
import Model

/// Syzygy tablebases for every ending with four pieces or fewer (kings
/// included), probed through Fathom. A probe gives the exact result with best
/// play, where the engine's score only points to one.

public enum Tablebase {
  /// The most pieces, kings included, the bundled tables cover.
  public static let maxPieces = 4

  private static let ready: Bool = {
    guard let url = Bundle.module.url(forResource: "Syzygy", withExtension: nil) else { return false }
    return url.path.withCString { tb_init($0) }
  }()

  /// The result for the side to move in `fen`, or nil when the tables don't
  /// cover it: more than four pieces, castling rights left, or a failed probe.
  public static func probe(_ fen: String) -> GameResult? {
    let fields = fen.split(separator: " ").map(String.init)
    guard fields.count >= 2 else { return nil }
    if fields.count > 2 && fields[2] != "-" { return nil }
    var white: UInt64 = 0, black: UInt64 = 0, kings: UInt64 = 0, queens: UInt64 = 0
    var rooks: UInt64 = 0, bishops: UInt64 = 0, knights: UInt64 = 0, pawns: UInt64 = 0
    var count = 0
    var rank = 7, file = 0
    for ch in fields[0] {
      if ch == "/" { rank -= 1; file = 0; continue }
      if let skip = ch.wholeNumberValue { file += skip; continue }
      guard (0..<8).contains(rank), (0..<8).contains(file) else { return nil }
      let bit: UInt64 = 1 << UInt64(rank * 8 + file)
      if ch.isUppercase { white |= bit } else { black |= bit }
      switch ch.lowercased() {
      case "k": kings |= bit
      case "q": queens |= bit
      case "r": rooks |= bit
      case "b": bishops |= bit
      case "n": knights |= bit
      case "p": pawns |= bit
      default: return nil
      }
      count += 1
      file += 1
    }
    guard count <= maxPieces, ready else { return nil }
    var ep: UInt32 = 0
    if fields.count > 3, fields[3] != "-", let sq = square(fields[3]) { ep = UInt32(sq) }
    let wdl = tb_probe_wdl_impl(white, black, kings, queens, rooks, bishops, knights, pawns, ep, fields[1] == "w")
    switch wdl {
    case UInt32(TB_WIN): return .win
    case UInt32(TB_LOSS): return .loss
    case UInt32(TB_DRAW), UInt32(TB_CURSED_WIN), UInt32(TB_BLESSED_LOSS): return .draw
    default: return nil
    }
  }

  /// The result for `color` in `fen`, whoever is to move.
  public static func probe(_ fen: String, for color: Color) -> GameResult? {
    guard let r = probe(fen) else { return nil }
    let toMove = fen.split(separator: " ").dropFirst().first == "w" ? Color.w : Color.b
    return toMove == color ? r : r.flipped
  }

  private static func square(_ s: String) -> Int? {
    let chars = Array(s)
    guard chars.count == 2, let f = chars[0].asciiValue, let r = chars[1].wholeNumberValue,
      (97...104).contains(f), (1...8).contains(r)
    else { return nil }
    return (r - 1) * 8 + Int(f - 97)
  }
}
