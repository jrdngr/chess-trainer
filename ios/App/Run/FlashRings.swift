import ChessCore
import SwiftUI

/// The Undefended flash over the board: a pulsing red ring on each piece
/// your held move leaves loose, and Take back at the top. `FlashRing`.
struct FlashRings: View {
  let loose: [String]
  let orientation: ChessCore.Color
  let onTakeBack: () -> Void
  @State private var bright = false

  var body: some View {
    GeometryReader { geo in
      let cell = min(geo.size.width, geo.size.height) / 8
      ZStack(alignment: .topLeading) {
        ForEach(loose, id: \.self) { square in
          let (col, row) = place(square)
          Circle().strokeBorder(Theme.bad, lineWidth: 4)
            .shadow(color: Theme.bad.opacity(0.7), radius: 9)
            .frame(width: cell, height: cell)
            .offset(x: CGFloat(col) * cell, y: CGFloat(row) * cell)
            .opacity(bright ? 1 : 0.55)
        }
      }
      .allowsHitTesting(false)
    }
    .overlay(alignment: .top) {
      Button("Take back", action: onTakeBack)
        .font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.text)
        .padding(.horizontal, 14).frame(minHeight: 36)
        .background(Capsule().fill(Theme.surface2))
        .buttonStyle(.plain).padding(.top, 10)
    }
    .onAppear {
      withAnimation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true)) { bright = true }
    }
  }

  private func place(_ square: String) -> (Int, Int) {
    let file = Int(square.unicodeScalars.first!.value) - 97
    let rank = Int(String(square.last!))! - 1
    return orientation == .w ? (file, 7 - rank) : (7 - file, rank)
  }
}
