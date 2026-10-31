import ChessCore
import Engine
import Model
import SwiftUI

/// The score, the bar of it that is White's, and the depth, over the board.
struct EvalRow: View {
  let best: EngineLine?
  let depth: Int

  var body: some View {
    HStack(spacing: 10) {
      Text(best.map(formatScore) ?? "\u{2014}").font(.system(size: 15, weight: .bold).monospacedDigit())
        .foregroundStyle(Theme.text).frame(minWidth: 50, alignment: .leading)
      GeometryReader { geo in
        Capsule().fill(Theme.surface3)
          .overlay(alignment: .leading) {
            Rectangle().fill(Color(hex: 0xf5f5f7)).frame(width: geo.size.width * winFraction(best))
              .animation(.easeOut(duration: 0.35), value: winFraction(best))
          }
          .clipShape(Capsule())
      }
      .frame(height: 6)
      Text("d\(depth)").font(.system(size: 12).monospacedDigit()).foregroundStyle(Theme.text3)
        .frame(minWidth: 30, alignment: .trailing)
    }
    .padding(.horizontal, 2).frame(minHeight: 22)
  }
}

/// The engine's section: its name and switch, then its lines, each a tap to play its first move.
struct EngineSection: View {
  let label: String
  let enabled: Bool
  let started: Bool
  let thinking: Bool
  let fen: String
  let lines: [SanLine]
  let onToggle: () -> Void
  let onPlay: (String) -> Void

  var body: some View {
    AnalysisSectionHead(title: label) {
      Button(action: onToggle) { AnalysisChip(text: enabled ? "On" : "Off", tone: enabled ? .on : .plain) }.buttonStyle(.plain)
    }
    if enabled {
      VStack(spacing: 0) {
        if lines.isEmpty {
          Text(!started ? "Starting\u{2026}" : thinking ? "Thinking\u{2026}" : "No lines")
            .font(.system(size: 13)).foregroundStyle(Theme.text3)
            .frame(maxWidth: .infinity, minHeight: 46, alignment: .leading).padding(.horizontal, 16)
        }
        ForEach(Array(lines.enumerated()), id: \.element.id) { i, line in
          if i > 0 { Rectangle().fill(.white.opacity(0.07)).frame(height: 1) }
          row(line)
        }
      }
      .background(RoundedRectangle(cornerRadius: 16).fill(Theme.surface))
      .clipShape(RoundedRectangle(cornerRadius: 16))
    }
  }

  private func row(_ line: SanLine) -> some View {
    Button {
      if let uci = line.line.pv.first, let move = applyUci(fen, uci) { onPlay(move.san) }
    } label: {
      HStack(alignment: .firstTextBaseline, spacing: 12) {
        Text(formatScore(line.line)).font(.system(size: 13.5, weight: .bold).monospacedDigit())
          .foregroundStyle((line.line.cp ?? 0) >= 0 ? Theme.text : Theme.text2).frame(minWidth: 48, alignment: .leading)
        Text(sansToMoveText(line.sans, fen)).font(.system(size: 13.5)).foregroundStyle(Theme.text2).lineLimit(1)
        Spacer(minLength: 0)
      }
      .padding(.horizontal, 16).padding(.vertical, 10).contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }
}
