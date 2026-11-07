import ChessCore
import Model
import SwiftUI

/// The first screen a new profile sees: what the app is, then a first game with tips, or Skip.
struct WelcomeView: View {
  let onTutorial: () -> Void
  let onSkip: () -> Void

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
      VStack(alignment: .leading, spacing: 16) {
        WelcomePoint(glyph: "\u{265E}", text: "A game for learning chess openings.")
        WelcomePoint(glyph: "\u{265F}\u{FE0E}", text: "Your openings are the cards.")
        WelcomePoint(glyph: "\u{265A}", text: "Each one is a real game until you blunder.")
      }
      .padding(.top, 22)
      Spacer(minLength: 0)
      BigButton(label: "Play the tutorial", action: onTutorial)
      SkipButton(label: "Skip", action: onSkip).frame(maxWidth: .infinity).padding(.top, 6).padding(.bottom, 8)
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

/// A line with a piece beside it, as on the welcome.
/// The pawn has an emoji form, so its glyph carries the text-style selector to take the accent like the others.
struct WelcomePoint: View {
  let glyph: String
  let text: String

  var body: some View {
    HStack(alignment: .top, spacing: 12) {
      Text(glyph).font(.system(size: 21)).foregroundStyle(Theme.accent)
        .frame(width: 32, height: 32).background(RoundedRectangle(cornerRadius: 10).fill(Theme.surface2))
      Text(text).font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.text)
        .fixedSize(horizontal: false, vertical: true).padding(.top, 5)
    }
  }
}
