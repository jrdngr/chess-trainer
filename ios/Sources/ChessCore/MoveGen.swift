import Foundation

extension Board {
  /// Legal moves in chess.js's order: squares a8 to h1, then castling.
  func moves(piece only: PieceType? = nil) -> [RawMove] {
    var out: [RawMove] = []
    let us = turn, them = us.other
    let push = us == .w ? -16 : 16
    let captures = us == .w ? [-17, -15] : [17, 15]
    let secondRank = us == .w ? 6 : 1

    func add(_ from: Int, _ to: Int, _ piece: PieceType, _ captured: PieceType? = nil, _ flags: Int = Flag.normal) {
      let r = rank(to)
      if piece == .p, r == 0 || r == 7 {
        for promotion in [PieceType.n, .b, .r, .q] {
          out.append(RawMove(color: us, from: from, to: to, piece: piece, captured: captured, promotion: promotion, flags: flags | Flag.promotion))
        }
      } else {
        out.append(RawMove(color: us, from: from, to: to, piece: piece, captured: captured, flags: flags))
      }
    }

    var from = 0
    while from <= 119 {
      if from & 0x88 != 0 { from += 8; continue }
      defer { from += 1 }
      guard let piece = squares[from], piece.color == us else { continue }
      if let only, only != piece.type { continue }
      if piece.type == .p {
        var to = from + push
        if squares[to] == nil {
          add(from, to, .p)
          to = from + 2 * push
          if rank(from) == secondRank, squares[to] == nil { add(from, to, .p, nil, Flag.bigPawn) }
        }
        for offset in captures {
          to = from + offset
          if to & 0x88 != 0 { continue }
          if let target = squares[to], target.color == them {
            add(from, to, .p, target.type, Flag.capture)
          } else if to == ep {
            add(from, to, .p, .p, Flag.epCapture)
          }
        }
      } else {
        for offset in pieceOffsets[piece.type]! {
          var to = from
          while true {
            to += offset
            if to & 0x88 != 0 { break }
            if let target = squares[to] {
              if target.color != us { add(from, to, piece.type, target.type, Flag.capture) }
              break
            }
            add(from, to, piece.type)
            if piece.type == .n || piece.type == .k { break }
          }
        }
      }
    }

    if only == nil || only == .k, let king = kings[us] {
      if castling[us]! & Flag.kside != 0,
        squares[king + 1] == nil, squares[king + 2] == nil,
        !attacked(by: them, king), !attacked(by: them, king + 1), !attacked(by: them, king + 2)
      {
        add(king, king + 2, .k, nil, Flag.kside)
      }
      if castling[us]! & Flag.qside != 0,
        squares[king - 1] == nil, squares[king - 2] == nil, squares[king - 3] == nil,
        !attacked(by: them, king), !attacked(by: them, king - 1), !attacked(by: them, king - 2)
      {
        add(king, king - 2, .k, nil, Flag.qside)
      }
    }

    return out.filter { !made($0).kingAttacked(us) }
  }

  var inCheck: Bool { kingAttacked(turn) }
  var isCheckmate: Bool { inCheck && moves().isEmpty }
  var isStalemate: Bool { !inCheck && moves().isEmpty }

  /// chess.js `isInsufficientMaterial`.
  var insufficientMaterial: Bool {
    var counts: [PieceType: Int] = [:]
    var bishops: [Int] = []
    var total = 0
    var color = 0
    var i = 0
    while i <= 119 {
      color = (color + 1) % 2
      if i & 0x88 != 0 { i += 7; i += 1; continue }
      if let piece = squares[i] {
        counts[piece.type, default: 0] += 1
        if piece.type == .b { bishops.append(color) }
        total += 1
      }
      i += 1
    }
    if total == 2 { return true }
    if total == 3, counts[.b] == 1 || counts[.n] == 1 { return true }
    if total == counts[.b, default: 0] + 2 {
      let sum = bishops.reduce(0, +)
      return sum == 0 || sum == bishops.count
    }
    return false
  }
}
