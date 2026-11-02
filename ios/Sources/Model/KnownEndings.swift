import ChessCore

/// Endings recognized on sight, past the tablebases' four pieces: the board
/// alone settles the result. Each one is claimed only in a quiet position (no
/// piece can be taken), so a tactic never hides behind a known result.

public struct KnownEnding: Equatable, Sendable {
  /// "Lucena", "Philidor", "Wrong bishop", "Rook pawn" or "Opposite bishops".
  public var name: String
  /// Who wins with best play; nil for a draw.
  public var winner: Color?
  public init(name: String, winner: Color?) {
    self.name = name
    self.winner = winner
  }

  public func result(for color: Color) -> EndResult {
    winner == nil ? .draw : winner == color ? .win : .loss
  }
}

extension Man {
  /// The rank counted from `color`'s side, 0 to 7.
  func up(_ color: Color) -> Int { rel(color, rank) }
  var light: Bool { (file + rank) % 2 == 1 }
}

private func kinds(_ men: [Man], _ color: Color) -> [PieceType] {
  men.filter { $0.color == color }.map(\.type).sorted { $0.rawValue < $1.rawValue }
}

/// No piece but a pawn can be taken by the side to move.
private func quiet(_ fen: String) -> Bool {
  !legalMoves(fen).contains { $0.captured != nil && $0.captured != .p }
}

/// The known ending on the board, if there is one.
public func knownEnding(_ fen: String) -> KnownEnding? {
  let men = Grid(fen).men
  guard men.count >= 4, men.count <= 12 else { return nil }
  for attacker in [Color.w, .b] {
    let defender = attacker.other
    let mine = kinds(men, attacker), theirs = kinds(men, defender)
    guard let king = men.first(where: { $0.type == .k && $0.color == attacker }),
      let them = men.first(where: { $0.type == .k && $0.color == defender })
    else { return nil }
    let pawns = men.filter { $0.type == .p && $0.color == attacker }

    // Rook and pawn against rook.
    if mine == [.k, .p, .r], theirs == [.k, .r], let pawn = pawns.first,
      !positionStatus(fen).check, quiet(fen)
    {
      let rook = men.first { $0.type == .r && $0.color == attacker }!
      let theirRook = men.first { $0.type == .r && $0.color == defender }!
      let pr = pawn.up(attacker)
      // Lucena: pawn on the seventh, its king in front, their king cut off by the rook's file.
      if (1...6).contains(pawn.file), pr == 6, king.file == pawn.file, king.up(attacker) == 7,
        abs(them.file - pawn.file) >= 2, rook.file > min(pawn.file, them.file), rook.file < max(pawn.file, them.file)
      {
        return KnownEnding(name: "Lucena", winner: attacker)
      }
      // Philidor: their king in front of the pawn, their rook holding the sixth, neither king nor pawn past the fifth.
      if pr <= 4, king.up(attacker) <= 4, abs(them.file - pawn.file) <= 1,
        them.up(attacker) >= 6, theirRook.up(attacker) == 5
      {
        return KnownEnding(name: "Philidor", winner: nil)
      }
    }

    // Pawns on one rook file, with or without a bishop that can't cover the corner, against a bare king in it.
    if theirs == [.k], !pawns.isEmpty, mine.allSatisfy({ $0 == .k || $0 == .p || $0 == .b }),
      mine.filter({ $0 == .b }).count <= 1
    {
      let file = pawns[0].file
      let corner = (file: file, rank: attacker == .w ? 7 : 0)
      let bishop = men.first { $0.type == .b && $0.color == attacker }
      let cornerLight = (corner.file + corner.rank) % 2 == 1
      if file == 0 || file == 7, pawns.allSatisfy({ $0.file == file }), bishop.map({ $0.light != cornerLight }) ?? true,
        max(abs(them.file - corner.file), abs(them.rank - corner.rank)) <= 1
      {
        return KnownEnding(name: bishop == nil ? "Rook pawn" : "Wrong bishop", winner: nil)
      }
    }

    // Bishops of opposite colors, one pawn up, their king blocking it.
    if mine == [.b, .k, .p], theirs == [.b, .k], let pawn = pawns.first, quiet(fen) {
      let mineB = men.first { $0.type == .b && $0.color == attacker }!
      let theirB = men.first { $0.type == .b && $0.color == defender }!
      if mineB.light != theirB.light, them.file == pawn.file, them.up(attacker) > pawn.up(attacker) {
        return KnownEnding(name: "Opposite bishops", winner: nil)
      }
    }
  }
  return nil
}
