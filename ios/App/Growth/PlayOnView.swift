import ChessCore
import Engine
import Game
import Model
import SwiftUI

/// A game carried on from the end of a line, against the engine: your own
/// colour, a short fixed think, take-backs a pair at a time, and nothing
/// recorded.
struct PlayOnView: View {
  let from: String
  let color: ChessCore.Color
  let label: String
  let onBack: () -> Void

  @Environment(AppStore.self) private var store
  @State private var game: PlayOnGame?

  var body: some View {
    Group {
      if let game { content(game) } else { Theme.background }
    }
    .onAppear { if game == nil { game = PlayOnGame(from: from, color: color, services: store.services) } }
    .onDisappear { game?.stop() }
  }

  private func content(_ game: PlayOnGame) -> some View {
    let fen = game.fen
    let status = game.status
    let engineTurn = game.engineTurn
    return VStack(spacing: 0) {
      AppBar(title: "Playing on", subtitle: label, onBack: onBack) {
        Text(game.best.map(formatScore) ?? "\u{2014}").font(.system(size: 12, weight: .semibold).monospacedDigit()).foregroundStyle(Theme.text2)
          .padding(.horizontal, 9).padding(.vertical, 3).frame(minWidth: 56).background(Capsule().fill(Theme.surface2))
      }
      if !status.gameOver {
        StatusLine(white: color == .w, text: engineTurn ? "Reply" : "Your move", busy: engineTurn).padding(.bottom, 4)
      }
      ScrollView {
        VStack(spacing: 0) {
          CapturedRow(fen: fen, orientation: color).padding(.bottom, 6)
          BoardView(
            fen: fen, orientation: color, interactive: !engineTurn && !status.gameOver,
            lastMove: lastMoveOf(game.sans, from), onMove: { move in game.play(move) }
          )
          .opacity(status.gameOver ? 0.55 : 1)
          Spacer().frame(height: 16)
          if let result = game.result {
            GrowthVerdict(tone: game.won ? .ok : .no, text: result)
          }
          if !game.sans.isEmpty {
            PlaySection(title: "From the end of the line").frame(maxWidth: .infinity)
            Text(sansToMoveText(game.sans, from)).font(.system(size: 13, design: .monospaced)).foregroundStyle(Theme.text2).lineSpacing(6)
              .frame(maxWidth: .infinity, alignment: .leading).padding(16)
              .background(RoundedRectangle(cornerRadius: 16).fill(Theme.surface))
          }
          Spacer().frame(height: 16)
          Button { game.takeBack() } label: {
            HStack(spacing: 8) { Icon(name: "prev", size: 18); Text("Take back") }.frame(maxWidth: .infinity)
          }
          .buttonStyle(PlayButtonStyle()).disabled(game.yourMoves == 0 || engineTurn)
          Button(action: onBack) { Text("Back to the line").frame(maxWidth: .infinity) }
            .buttonStyle(PlayButtonStyle(kind: .bare)).padding(.top, 8)
        }
        .padding(.horizontal, 16).padding(.top, 4).padding(.bottom, 20)
      }
    }
  }
}
