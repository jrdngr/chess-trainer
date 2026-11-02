import ChessCore
import Engine
import Model
import SwiftUI

/// What happens after a wrong move: the engine plays on from it and shows
/// the reply that punishes it, beside what the prepared move was worth.
struct WhySheet: View {
  /// The position that was asked about.
  let fen: String
  let side: ChessCore.Color
  let played: LegalMove
  let expected: LegalMove?
  let expectedSan: String?
  @Environment(\.dismiss) private var dismiss
  @State private var found: EngineLine?
  @State private var foundSans: [String] = []
  @State private var best: EngineLine?
  @State private var searched = false
  @State private var cursor = 1

  var body: some View {
    let line = [played.san] + foundSans.prefix(9)
    let fens = walkSan(line, fen).fens
    let at = min(cursor, fens.count - 1)
    ScrollView {
      VStack(spacing: 0) {
        HStack {
          Text("Why not \(played.san)?").font(.system(size: 22, weight: .heavy)).foregroundStyle(Theme.text)
          Spacer()
          IconButton(icon: "close") { dismiss() }
        }
        .padding(.bottom, 12)
        CompareCards(
          good: (expectedSan ?? "Playbook", expected == nil ? "\u{2014}" : score(best) ?? "\u{2026}"),
          bad: (played.san, score(found) ?? "\u{2026}"), badFirst: true)
        Spacer().frame(height: 8)
        BoardView(fen: fens[at], orientation: side, interactive: false, lastMove: at > 0 ? lastMoveOf(Array(line.prefix(at)), fen) : nil) { _ in }
        Spacer().frame(height: 8)
        MoveStrip(items: strip(line, fens, at), cursor: at, max: line.count) { cursor = max(0, min(line.count, $0)) }
        footnote
      }
      .padding(20)
    }
    .presentationDetents([.large]).presentationBackground(Theme.background)
    .task { await search() }
  }

  @ViewBuilder private var footnote: some View {
    let text = !searched ? "Playing it out\u{2026}"
      : foundSans.isEmpty ? "The engine finds nothing forced here \u{2014} this one is a matter of plan, not tactics."
      : "Rough estimate at depth \(found?.depth ?? 0), from the position after each move."
    Text(text).font(.system(size: 12)).foregroundStyle(Theme.text3).multilineTextAlignment(.center).padding(.top, 8)
  }

  private func strip(_ line: [String], _ fens: [String], _ at: Int) -> [StripItem] {
    line.enumerated().map { i, san in
      StripItem(
        san: san, label: fenTurn(fens[i]) == .w ? "\(fullmoveNumber(fens[i]))." : nil,
        tone: i == 0 ? .bad : .ghost, current: at == i + 1, seek: i + 1)
    }
  }

  /// A score read from the side that was to move.
  private func score(_ line: EngineLine?) -> String? {
    guard var line else { return nil }
    if side == .b {
      line.cp = line.cp.map { -$0 }
      line.mate = line.mate.map { -$0 }
    }
    return formatScore(line)
  }

  /// The move played first, so there is something to read while the prepared one is weighed.
  private func search() async {
    let engine = HintEngine.shared
    let limits = EngineLimits(movetime: 1500, multiPv: 1)
    let mine = await engine.analyse(played.after, limits).lines.first
    found = mine
    var at = played.after
    var sans: [String] = []
    for uci in mine?.pv ?? [] {
      guard let move = applyUci(at, uci) else { break }
      sans.append(move.san)
      at = move.after
    }
    foundSans = sans
    searched = true
    if let expected { best = await engine.analyse(expected.after, limits).lines.first }
  }
}
