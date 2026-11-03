import ChessCore
import SwiftUI

/// The material difference, as Lichess shows it: what each side is up,
/// with even trades left out. Yours first, wherever you are sitting; the
/// lead is named by color, "+3 white". Black pieces are edged in white so
/// they read on the dark background.
struct CapturedRow: View {
  var fen: String
  var orientation: ChessCore.Color

  var body: some View {
    let m = material(fen)
    let mine = orientation == .w ? m.byWhite : m.byBlack
    let theirs = orientation == .w ? m.byBlack : m.byWhite
    HStack(spacing: 1) {
      taken(mine, orientation.other)
      if !mine.isEmpty && !theirs.isEmpty { Spacer().frame(width: 16) }
      taken(theirs, orientation)
      Spacer(minLength: 0)
      badge(m.lead)
    }
    .frame(minHeight: 22).padding(.horizontal, 2)
    // Never widens the screen.
    .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
  }

  @ViewBuilder private func badge(_ lead: Int) -> some View {
    if lead != 0 {
      let white = lead > 0
      Text("+\(abs(lead)) \(white ? "white" : "black")")
        .font(.system(size: 11.5, weight: .semibold))
        .foregroundStyle(white ? SwiftUI.Color(hex: 0x111111) : SwiftUI.Color(hex: 0xe8e8ee))
        .padding(.horizontal, 9).padding(.vertical, 3)
        .background(Capsule().fill(white ? SwiftUI.Color(hex: 0xf2f2f4) : SwiftUI.Color(hex: 0x2a2a31)))
        .fixedSize()
    }
  }

  private func taken(_ pieces: [PieceType], _ color: ChessCore.Color) -> some View {
    ForEach(Array(pieces.enumerated()), id: \.offset) { _, type in
      PieceView(piece: BoardPiece(square: "a1", type: type, color: color), size: 18, outlined: true)
    }
  }
}
