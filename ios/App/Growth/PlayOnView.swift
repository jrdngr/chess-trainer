import ChessCore
import Engine
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
  @State private var sans: [String] = []
  @State private var best: EngineLine?
  private static let engine = EngineSlot()

  var body: some View {
    let fens = walkSan(sans, from).fens
    let fen = fens.last!
    let status = positionStatus(fen)
    let engineTurn = fenTurn(fen) != color
    let won = status.checkmate && fenTurn(fen) != color
    VStack(spacing: 0) {
      AppBar(title: "Playing on", subtitle: label, onBack: onBack) {
        Text(best.map(formatScore) ?? "\u{2014}").font(.system(size: 12, weight: .semibold).monospacedDigit()).foregroundStyle(Theme.text2)
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
            lastMove: lastMoveOf(sans, from), onMove: { move in
              Haptics.buzz(10, on: store.state.settings.hapticFeedback)
              sans.append(move.san)
            }
          )
          .opacity(status.gameOver ? 0.55 : 1)
          Spacer().frame(height: 16)
          if status.gameOver {
            GrowthVerdict(tone: won ? .ok : .no, text: result(status, won))
          }
          if !sans.isEmpty {
            PlaySection(title: "From the end of the line").frame(maxWidth: .infinity)
            Text(sansToMoveText(sans, from)).font(.system(size: 13, design: .monospaced)).foregroundStyle(Theme.text2).lineSpacing(6)
              .frame(maxWidth: .infinity, alignment: .leading).padding(16)
              .background(RoundedRectangle(cornerRadius: 16).fill(Theme.surface))
          }
          Spacer().frame(height: 16)
          Button { sans.removeLast(min(2, sans.count)) } label: {
            HStack(spacing: 8) { Icon(name: "prev", size: 18); Text("Take back") }.frame(maxWidth: .infinity)
          }
          .buttonStyle(PlayButtonStyle()).disabled(yourMoves(fens) == 0 || engineTurn)
          Button(action: onBack) { Text("Back to the line").frame(maxWidth: .infinity) }
            .buttonStyle(PlayButtonStyle(kind: .bare)).padding(.top, 8)
        }
        .padding(.horizontal, 16).padding(.top, 4).padding(.bottom, 20)
      }
    }
    .task(id: fen) { await think(fen, engineTurn && !status.gameOver) }
  }

  /// The engine's eval, and its move when it is to play.
  private func think(_ fen: String, _ moving: Bool) async {
    best = nil
    if moving { try? await Task.sleep(for: .milliseconds(120)) }
    let snap = await Self.engine().analyse(fen, EngineLimits(movetime: 700, multiPv: 1))
    guard !Task.isCancelled else { return }
    best = snap.lines.first
    if moving, let uci = best?.pv.first, let move = applyUci(fen, uci) { sans.append(move.san) }
  }

  private func yourMoves(_ fens: [String]) -> Int {
    sans.indices.filter { fenTurn(fens[$0]) == color }.count
  }

  private func result(_ status: PositionStatus, _ won: Bool) -> String {
    if status.checkmate { return won ? "Checkmate \u{2014} you won" : "Checkmate \u{2014} you lost" }
    return status.stalemate ? "Stalemate" : "Drawn"
  }
}
