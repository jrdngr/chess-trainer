import ChessCore

/// What a plan reads off the board beyond the pawns: where the kings are,
/// which pieces are left, the files, passed pawns.

/// Where a king stands: castled to either wing, or still in the middle.
public enum KingSpot: String, Sendable {
  case short, long, center
}

/// The board as plans read it.
public struct PlanFacts: Sendable {
  let men: [BoardPiece]
  let rights: Substring

  public init(_ fen: String) {
    men = piecesFromFen(fen)
    let fields = fen.split(separator: " ")
    rights = fields.count > 2 ? fields[2] : "-"
  }

  /// A king on its back two ranks, past the e-file is short, before the d-file is long.
  public func king(_ color: Color) -> KingSpot {
    guard let k = men.first(where: { $0.type == .k && $0.color == color }) else { return .center }
    let (file, rank) = coords(k.square)
    guard rel(color, rank) <= 1 else { return .center }
    return file >= 5 ? .short : file <= 2 ? .long : .center
  }

  /// The side may still castle that way.
  public func canCastle(_ color: Color, long: Bool) -> Bool {
    let flag: Character = long ? (color == .w ? "Q" : "q") : (color == .w ? "K" : "k")
    return rights.contains(flag)
  }

  public func count(_ color: Color, _ type: PieceType) -> Int {
    men.filter { $0.color == color && $0.type == type }.count
  }

  /// A bishop of this color on squares of this shade.
  public func bishop(_ color: Color, light: Bool) -> Bool {
    men.contains { $0.color == color && $0.type == .b && isLight($0.square) == light }
  }

  public var queensOn: Bool { count(.w, .q) > 0 && count(.b, .q) > 0 }

  public func pawn(_ color: Color, on square: String) -> Bool {
    men.contains { $0.color == color && $0.type == .p && $0.square == square }
  }

  /// This side's pawns on a file, 0...7.
  func pawns(_ color: Color, file: Int) -> [BoardPiece] {
    men.filter { $0.color == color && $0.type == .p && coords($0.square).file == file }
  }

  /// No pawn of this side on the file.
  public func fileFree(_ color: Color, _ file: Int) -> Bool { pawns(color, file: file).isEmpty }

  /// This side's pawns of this shade that have left home, for a bad bishop.
  func pawnsOn(_ color: Color, light: Bool) -> Int {
    men.filter { $0.color == color && $0.type == .p && isLight($0.square) == light && rel(color, coords($0.square).rank) > 1 }.count
  }

  /// A rook of this side on the file.
  func rook(_ color: Color, file: Int) -> Bool {
    men.contains { $0.color == color && $0.type == .r && coords($0.square).file == file }
  }
}

/// a1 is dark.
public func isLight(_ square: String) -> Bool {
  let (file, rank) = coords(square)
  return (file + rank) % 2 == 1
}

/* ── conditions and checks ── */

/// A side named by the structure: `a`, the side it is named after, or `b`.
public enum PlanSide: String, Sendable {
  case a, b
}

/// A condition a plan or step needs from the board. Squares and bishop shades
/// are written for side `a` as White, and placed for the board: with `a` Black
/// the board is turned over, so a shade turns too.
public enum Need: Equatable, Sendable {
  case castledShort(PlanSide)
  case notCastledShort(PlanSide)
  case castledLong(PlanSide)
  case notCastledLong(PlanSide)
  case queens
  case noQueens
  case piece(PlanSide, PieceType)
  case bishop(PlanSide, light: Bool)
  case pawn(PlanSide, String)
  /// A pawn of that side anywhere on the file, a...h.
  case pawnFile(PlanSide, String)
}

/// How a step is known done or gone, beyond reaching a square.
public enum StepCheck: Equatable, Sendable {
  /// Castle to this wing.
  case castle(long: Bool)
  /// Trade bishops of this shade: done once theirs is gone, gone once yours goes first.
  case trade(light: Bool)
  /// A rook on this file, a...h.
  case file(String)
  /// Keep your bishop of this shade: gone once it goes, never ticked.
  case keepBishop(light: Bool)
}

func colorOf(_ side: PlanSide, a: Color) -> Color { side == .a ? a : a.other }

/// Whether a condition holds, side `a` being this color.
public func holds(_ need: Need, _ facts: PlanFacts, a: Color) -> Bool {
  switch need {
  case .castledShort(let s): return facts.king(colorOf(s, a: a)) == .short
  case .notCastledShort(let s): return facts.king(colorOf(s, a: a)) != .short
  case .castledLong(let s): return facts.king(colorOf(s, a: a)) == .long
  case .notCastledLong(let s): return facts.king(colorOf(s, a: a)) != .long
  case .queens: return facts.queensOn
  case .noQueens: return !facts.queensOn
  case .piece(let s, let t): return facts.count(colorOf(s, a: a), t) > 0
  case .bishop(let s, let light): return facts.bishop(colorOf(s, a: a), light: placeShade(light, a))
  case .pawn(let s, let square): return facts.pawn(colorOf(s, a: a), on: placeSquare(square, a))
  case .pawnFile(let s, let file): return !facts.fileFree(colorOf(s, a: a), fileIndex(file))
  }
}

/// A template's shade as it stands on the board.
func placeShade(_ light: Bool, _ a: Color) -> Bool { a == .w ? light : !light }

func fileIndex(_ file: String) -> Int { Int(file.utf8.first!) - 97 }
