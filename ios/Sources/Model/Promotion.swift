import ChessCore

/// What a pawn can become on `to`: queen, knight, rook, bishop, in that order,
/// kept to those among `moves`. Empty when the move from `from` to `to` is not a promotion.
public func promotionChoices(_ moves: [LegalMove], from: String, to: String) -> [LegalMove] {
  let promotions = moves.filter { $0.from == from && $0.to == to && $0.promotion != nil }
  return [PieceType.q, .n, .r, .b].compactMap { kind in promotions.first { $0.promotion == kind } }
}
