import ChessCore
import Model
import SwiftUI

/// The first screen a new profile sees: what the app is, then Get started.
struct WelcomeView: View {
  let onStart: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      ZStack {
        card(["e4", "c5"], .b).rotationEffect(.degrees(-11)).offset(x: -78, y: 14).opacity(0.75)
        card(["d4", "d5", "c4", "e6"], .b).rotationEffect(.degrees(11)).offset(x: 78, y: 14).opacity(0.75)
        card(["e4", "e5", "Nf3", "Nc6", "Bc4"], .w)
          .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.accent, lineWidth: 1.5))
      }
      .frame(maxWidth: .infinity).frame(height: 190).padding(.top, 40)
      Text("Flash cards you play").font(.system(size: 30, weight: .heavy)).tracking(-0.9).foregroundStyle(Theme.text)
        .padding(.top, 24)
      Text("Your openings are the cards. Play until you blunder.")
        .font(.system(size: 17)).foregroundStyle(Theme.text2).lineSpacing(3)
        .fixedSize(horizontal: false, vertical: true).padding(.top, 10)
      Spacer(minLength: 0)
      BigButton(label: "Get started", action: onStart).padding(.bottom, 16)
    }
    .padding(.horizontal, 20)
    .background(Theme.background.ignoresSafeArea())
  }

  private func card(_ sans: [String], _ color: ChessCore.Color) -> some View {
    VStack(alignment: .leading, spacing: 9) {
      MiniBoard(sans: sans, orientation: color, size: 116, lastMove: true).clipShape(RoundedRectangle(cornerRadius: 6))
      Capsule().fill(Theme.surface3).frame(width: 80, height: 6)
    }
    .padding(8)
    .background(RoundedRectangle(cornerRadius: 14).fill(Theme.surface))
    .shadow(color: .black.opacity(0.55), radius: 15, y: 14)
  }
}
