import ChessCore
import Model
import SwiftUI

/// A still board of the position a move order reaches: `MiniBoard` in
/// `Selection.tsx`. `lastMove` lights the move that reached it.
struct MiniBoard: View {
  var sans: [String]
  var orientation: ChessCore.Color
  var size: CGFloat = 96
  var lastMove = false
  @Environment(\.boardLook) private var look

  var body: some View {
    let fen = walkSan(sans).fens.last!
    let pieces = Dictionary(piecesFromFen(fen).map { ($0.square, $0) }, uniquingKeysWith: { a, _ in a })
    let last = lastMove ? lastMoveOf(sans) : nil
    let cell = size / 8
    Canvas { context, _ in
      for row in 0..<8 {
        for col in 0..<8 {
          let rect = CGRect(x: CGFloat(col) * cell, y: CGFloat(row) * cell, width: cell, height: cell)
          context.fill(Path(rect), with: .color((row + col) % 2 == 0 ? look.theme.light : look.theme.dark))
          let sq = square(col, row)
          if let last, last.from == sq || last.to == sq {
            context.fill(Path(rect), with: .color(SwiftUI.Color(red: 170 / 255, green: 160 / 255, blue: 1).opacity(0.55)))
          }
        }
      }
    }
    .overlay(alignment: .topLeading) {
      ForEach(Array(pieces.keys), id: \.self) { sq in
        let (col, row) = position(sq)
        PieceView(piece: pieces[sq]!, size: cell * 0.86)
          .frame(width: cell, height: cell)
          .offset(x: CGFloat(col) * cell, y: CGFloat(row) * cell)
      }
    }
    .frame(width: size, height: size)
  }

  private func square(_ col: Int, _ row: Int) -> String {
    let file = orientation == .w ? col : 7 - col
    let rank = orientation == .w ? 7 - row : row
    return String(UnicodeScalar(UInt8(97 + file))) + String(rank + 1)
  }

  private func position(_ sq: String) -> (Int, Int) {
    let u = Array(sq.utf8)
    let file = Int(u[0]) - 97, rank = Int(u[1]) - 49
    return orientation == .w ? (file, 7 - rank) : (7 - file, rank)
  }
}
