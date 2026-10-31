import Book
import ChessCore
import Engine
import Model
import SwiftUI

/// Analyze, over the end screen: the run's line move by move, the engine's
/// score in White's frame and its best lines, and Back to the end screen.
/// The full Analysis tab comes with phase 4.
struct AnalysisView: View {
  let line: [String]
  let orientation: ChessCore.Color
  let index: ReferenceIndex
  let engine: ChessEngine
  let onBack: () -> Void

  @State private var cursor: Int
  @State private var lines: [EngineLine] = []
  @State private var thinking = false

  init(line: [String], orientation: ChessCore.Color, index: ReferenceIndex, engine: ChessEngine, onBack: @escaping () -> Void) {
    self.line = line
    self.orientation = orientation
    self.index = index
    self.engine = engine
    self.onBack = onBack
    _cursor = State(initialValue: line.count)
  }

  private var visible: [String] { Array(line.prefix(cursor)) }
  private var fen: String { walkSan(visible).fens.last! }

  var body: some View {
    VStack(spacing: 10) {
      HStack {
        Button(action: onBack) { Label("Back", systemImage: "chevron.left") }.foregroundStyle(Theme.text2)
        Spacer()
        Text(openingNameForPath(index, visible)?.name ?? "Analysis").font(.headline).foregroundStyle(Theme.text).lineLimit(1)
        Spacer()
      }
      .padding(.horizontal).padding(.top, 10)
      HStack(spacing: 6) {
        evalBar
        BoardView(fen: fen, orientation: orientation, interactive: false, lastMove: lastMoveOf(visible), arrows: bestArrow, onMove: { _ in })
      }
      .aspectRatio(1.04, contentMode: .fit)
      .padding(.horizontal, 6)
      HStack(spacing: 28) {
        Button { cursor = 0 } label: { Image(systemName: "backward.end.fill") }.disabled(cursor == 0)
        Button { cursor -= 1 } label: { Image(systemName: "chevron.left") }.disabled(cursor == 0)
        Button { cursor += 1 } label: { Image(systemName: "chevron.right") }.disabled(cursor >= line.count)
        Button { cursor = line.count } label: { Image(systemName: "forward.end.fill") }.disabled(cursor >= line.count)
      }
      .font(.title3).foregroundStyle(Theme.text)
      Text(sansToMoveText(visible).isEmpty ? "Start position" : sansToMoveText(visible))
        .font(.footnote.monospaced()).foregroundStyle(Theme.text2).lineLimit(2).padding(.horizontal)
      VStack(alignment: .leading, spacing: 6) {
        if thinking && lines.isEmpty { ProgressView().controlSize(.small) }
        ForEach(lines.prefix(3), id: \.multipv) { l in
          HStack(alignment: .top) {
            Text(formatScore(l)).font(.subheadline.monospacedDigit().bold()).foregroundStyle(Theme.text).frame(width: 64, alignment: .leading)
            Text(sanLine(l)).font(.subheadline).foregroundStyle(Theme.text2).lineLimit(1)
          }
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal)
      Spacer()
    }
    .task(id: fen) { await analyse() }
  }

  private var evalBar: some View {
    GeometryReader { geo in
      let white = winFraction(lines.first)
      VStack(spacing: 0) {
        Rectangle().fill(orientation == .w ? Color.black : Color.white).frame(height: geo.size.height * (orientation == .w ? 1 - white : white))
        Rectangle().fill(orientation == .w ? Color.white : Color.black)
      }
      .animation(.easeOut(duration: 0.3), value: white)
    }
    .frame(width: 10)
    .clipShape(RoundedRectangle(cornerRadius: 3))
  }

  private var bestArrow: [BoardArrow] {
    guard let uci = lines.first?.pv.first, let move = applyUci(fen, uci) else { return [] }
    return [BoardArrow(from: move.from, to: move.to, color: Theme.good)]
  }

  /// A line's first moves as SAN.
  private func sanLine(_ l: EngineLine) -> String {
    var at = fen
    var out: [String] = []
    for uci in l.pv.prefix(6) {
      guard let move = applyUci(at, uci) else { break }
      out.append(move.san)
      at = move.after
    }
    return out.joined(separator: " ")
  }

  private func analyse() async {
    lines = []
    if positionStatus(fen).gameOver { return }
    thinking = true
    let snap = await engine.analyse(fen, EngineLimits(depth: 16, movetime: 2000, multiPv: 3))
    guard !Task.isCancelled else { return }
    lines = snap.lines
    thinking = false
  }
}
