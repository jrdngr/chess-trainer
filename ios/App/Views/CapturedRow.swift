import ChessCore
import SwiftUI

/// What has come off the board, and who is ahead by how much: `Captured`
/// in `Board.tsx`. Yours first, wherever you are sitting; the lead is named
/// by colour, "+3 white".
struct CapturedRow: View {
  var fen: String
  var orientation: ChessCore.Color

  var body: some View {
    let m = material(fen)
    let mine = orientation == .w ? m.byWhite : m.byBlack
    let theirs = orientation == .w ? m.byBlack : m.byWhite
    HStack(spacing: 1) {
      taken(mine, orientation.other)
      if !mine.isEmpty && !theirs.isEmpty { Spacer().frame(width: 10) }
      taken(theirs, orientation)
      Spacer()
      if m.lead != 0 {
        let white = m.lead > 0
        Text("+\(abs(m.lead)) \(white ? "white" : "black")")
          .font(.system(size: 11.5, weight: .semibold))
          .foregroundStyle(white ? SwiftUI.Color(hex: 0x111111) : SwiftUI.Color(hex: 0xe8e8ee))
          .padding(.horizontal, 9).padding(.vertical, 3)
          .background(Capsule().fill(white ? SwiftUI.Color(hex: 0xf2f2f4) : SwiftUI.Color(hex: 0x2a2a31)))
      }
    }
    .frame(minHeight: 22).padding(.horizontal, 2)
  }

  private func taken(_ pieces: [PieceType], _ color: ChessCore.Color) -> some View {
    ForEach(Array(pieces.enumerated()), id: \.offset) { _, type in
      PieceView(piece: BoardPiece(square: "a1", type: type, color: color), size: 18).opacity(0.85)
    }
  }
}
