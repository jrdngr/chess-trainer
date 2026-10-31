/// The chess the app needs, by FEN: `src/chess/core.ts`.

public let START_FEN = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"

public struct LegalMove: Equatable, Sendable {
  public var from: String
  public var to: String
  public var san: String
  public var uci: String
  public var promotion: PieceType?
  public var piece: PieceType
  public var captured: PieceType?
  /// FEN after the move.
  public var after: String
}

public struct BoardPiece: Equatable, Sendable {
  public var square: String
  public var type: PieceType
  public var color: Color
}

/// A position key ignores the move counters, so transpositions meet.
public func positionKey(_ fen: String) -> String {
  fen.split(separator: " ", omittingEmptySubsequences: false).prefix(4).joined(separator: " ")
}

public func fenTurn(_ fen: String) -> Color {
  let parts = fen.split(separator: " ", omittingEmptySubsequences: false)
  return parts.count > 1 && parts[1] == "b" ? .b : .w
}

public func fullmoveNumber(_ fen: String) -> Int {
  let parts = fen.split(separator: " ", omittingEmptySubsequences: false)
  return parts.count > 5 ? Int(parts[5]) ?? 1 : 1
}

private func legalMove(_ board: Board, _ move: RawMove, _ all: [RawMove]) -> LegalMove {
  LegalMove(
    from: algebraic(move.from),
    to: algebraic(move.to),
    san: board.san(move, among: all),
    uci: algebraic(move.from) + algebraic(move.to) + (move.promotion?.rawValue ?? ""),
    promotion: move.promotion,
    piece: move.piece,
    captured: move.captured,
    after: board.made(move).fen
  )
}

public func legalMoves(_ fen: String) -> [LegalMove] {
  guard let board = Board(fen: fen) else { return [] }
  let all = board.moves()
  return all.map { legalMove(board, $0, all) }
}

/// The legal moves as SAN only.
public func legalSans(_ fen: String) -> [String] {
  guard let board = Board(fen: fen) else { return [] }
  let all = board.moves()
  return all.map { board.san($0, among: all) }
}

/// Apply a move given as SAN. Nil when it is illegal.
public func applySan(_ fen: String, _ san: String) -> LegalMove? {
  guard let board = Board(fen: fen), let move = board.move(fromSan: san) else { return nil }
  return legalMove(board, move, board.moves())
}

/// Apply a move given as squares, with a promotion when one is needed.
public func applyMove(_ fen: String, from: String, to: String, promotion: PieceType? = nil) -> LegalMove? {
  guard let board = Board(fen: fen), let f = ox88(from), let t = ox88(to) else { return nil }
  let all = board.moves()
  // As chess.js: a promotion has to be named.
  guard let move = all.first(where: { $0.from == f && $0.to == t && ($0.promotion == nil || $0.promotion == promotion) }) else {
    return nil
  }
  return legalMove(board, move, all)
}

public func applyUci(_ fen: String, _ uci: String) -> LegalMove? {
  let chars = Array(uci)
  guard chars.count >= 4 else { return nil }
  let promo = chars.count > 4 ? PieceType(rawValue: String(chars[4])) : nil
  return applyMove(fen, from: String(chars[0...1]), to: String(chars[2...3]), promotion: promo)
}

/// Walk SAN moves from a start. Stops at the first illegal one.
public func walkSan(_ sans: [String], _ startFen: String = START_FEN) -> (fens: [String], moves: [LegalMove]) {
  var fens = [startFen]
  var moves: [LegalMove] = []
  var fen = startFen
  for san in sans {
    guard let move = applySan(fen, san) else { break }
    moves.append(move)
    fen = move.after
    fens.append(fen)
  }
  return (fens, moves)
}

/// The squares of a line's last move.
public func lastMoveOf(_ sans: [String], _ startFen: String = START_FEN) -> (from: String, to: String)? {
  guard !sans.isEmpty else { return nil }
  let fens = walkSan(Array(sans.dropLast()), startFen).fens
  guard let move = applySan(fens.last!, sans.last!) else { return nil }
  return (move.from, move.to)
}

public struct PositionStatus: Equatable, Sendable {
  public var check: Bool
  public var checkmate: Bool
  public var stalemate: Bool
  public var draw: Bool
  public var gameOver: Bool
}

public func positionStatus(_ fen: String) -> PositionStatus {
  guard let board = Board(fen: fen) else {
    return PositionStatus(check: false, checkmate: false, stalemate: false, draw: false, gameOver: false)
  }
  let checkmate = board.isCheckmate
  let stalemate = board.isStalemate
  let draw = board.halfMoves >= 100 || stalemate || board.insufficientMaterial
  return PositionStatus(check: board.inCheck, checkmate: checkmate, stalemate: stalemate, draw: draw, gameOver: checkmate || draw)
}

public func piecesFromFen(_ fen: String) -> [BoardPiece] {
  guard let board = Board(fen: fen) else { return [] }
  var out: [BoardPiece] = []
  for sq in 0..<128 where sq & 0x88 == 0 {
    if let piece = board.squares[sq] { out.append(BoardPiece(square: algebraic(sq), type: piece.type, color: piece.color)) }
  }
  return out
}

public func kingSquare(_ fen: String, _ color: Color) -> String? {
  piecesFromFen(fen).first { $0.type == .k && $0.color == color }?.square
}

/// What a piece is worth, for the material count.
public let PIECE_VALUES: [PieceType: Int] = [.p: 1, .n: 3, .b: 3, .r: 5, .q: 9, .k: 0]

public struct Material: Equatable, Sendable {
  public var byWhite: [PieceType]
  public var byBlack: [PieceType]
  public var lead: Int
}

/// What has come off the board, and who is ahead.
public func material(_ fen: String) -> Material {
  let fullSide: [PieceType] = [.p, .p, .p, .p, .p, .p, .p, .p, .n, .n, .b, .b, .r, .r, .q]
  var left: [Color: [PieceType]] = [.w: [], .b: []]
  var lead = 0
  for piece in piecesFromFen(fen) {
    left[piece.color]!.append(piece.type)
    lead += (piece.color == .w ? 1 : -1) * PIECE_VALUES[piece.type]!
  }
  func taken(_ side: [PieceType]) -> [PieceType] {
    var rest = side
    var out: [PieceType] = []
    for type in fullSide {
      if let at = rest.firstIndex(of: type) { rest.remove(at: at) } else { out.append(type) }
    }
    return out
  }
  return Material(byWhite: taken(left[.b]!), byBlack: taken(left[.w]!), lead: lead)
}

/// A SAN sequence as numbered move text: "1.e4 c5" reads "1. e4 c5".
public func sansToMoveText(_ sans: [String], _ startFen: String = START_FEN) -> String {
  var fen = startFen
  var parts: [String] = []
  var first = true
  for san in sans {
    let n = fullmoveNumber(fen)
    if fenTurn(fen) == .w { parts.append("\(n).") } else if first { parts.append("\(n)...") }
    parts.append(san)
    first = false
    guard let move = applySan(fen, san) else { break }
    fen = move.after
  }
  return parts.joined(separator: " ")
}
