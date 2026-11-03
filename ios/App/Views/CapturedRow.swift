import ChessCore
import SwiftUI

/// What has come off the board, and who is ahead by how much.
/// Yours first, wherever you are sitting; the lead is named
/// by color, "+3 white". Black pieces are edged in white so they read on
/// the dark background. When both sides don't fit on one line (an endgame
/// has most pieces gone), each side takes its own row, smaller if need be.
struct CapturedRow: View {
  var fen: String
  var orientation: ChessCore.Color

  var body: some View {
    let m = material(fen)
    let mine = orientation == .w ? m.byWhite : m.byBlack
    let theirs = orientation == .w ? m.byBlack : m.byWhite
    ViewThatFits(in: .horizontal) {
      HStack(spacing: 1) {
        taken(mine, orientation.other, 18)
        if !mine.isEmpty && !theirs.isEmpty { Spacer().frame(width: 16) }
        taken(theirs, orientation, 18)
        Spacer()
        badge(m.lead)
      }
      rows(mine, theirs, m.lead, 18)
      rows(mine, theirs, m.lead, 14)
    }
    .frame(minHeight: 22).padding(.horizontal, 2)
    // Never widens the screen, even if nothing fits.
    .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
  }

  /// Yours on the first row with the lead, theirs on the second.
  private func rows(_ mine: [PieceType], _ theirs: [PieceType], _ lead: Int, _ size: CGFloat) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      HStack(spacing: 1) {
        taken(mine, orientation.other, size)
        Spacer()
        badge(lead)
      }
      HStack(spacing: 1) {
        taken(theirs, orientation, size)
        Spacer()
      }
    }
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

  private func taken(_ pieces: [PieceType], _ color: ChessCore.Color, _ size: CGFloat) -> some View {
    ForEach(Array(pieces.enumerated()), id: \.offset) { _, type in
      PieceView(piece: BoardPiece(square: "a1", type: type, color: color), size: size, outlined: true)
    }
  }
}
