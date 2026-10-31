import ChessCore
import SwiftUI

/// The named lines that continue the board's moves, each a card that opens its sheet.
struct NamedLines: View {
  let lines: [BookLine]
  let onPick: (BookLine) -> Void

  var body: some View {
    AnalysisSectionHead(title: "Named lines") {
      if !lines.isEmpty { Text("\(lines.count) from here").font(.system(size: 12)).foregroundStyle(Theme.text3) }
    }
    if lines.isEmpty {
      AnalysisEmpty(title: "No named lines from here", hint: "Step back to see more")
    } else {
      VStack(spacing: 10) {
        ForEach(lines) { line in card(line) }
      }
    }
  }

  private func card(_ line: BookLine) -> some View {
    Button { onPick(line) } label: {
      VStack(alignment: .leading, spacing: 8) {
        HStack {
          VStack(alignment: .leading, spacing: 2) {
            Text(line.name).font(.system(size: 16, weight: .bold)).foregroundStyle(Theme.text)
            Text(meta(line)).font(.system(size: 12)).foregroundStyle(Theme.text3)
          }
          Spacer(minLength: 0)
          Icon(name: "chevron", size: 18).foregroundStyle(Theme.text)
        }
        Text(line.summary).font(.system(size: 13)).foregroundStyle(Theme.text2).lineSpacing(3).multilineTextAlignment(.leading)
      }
      .frame(maxWidth: .infinity, alignment: .leading).padding(16)
      .background(RoundedRectangle(cornerRadius: 16).fill(Theme.surface))
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }

  private func meta(_ line: BookLine) -> String {
    let side = line.forColor == .w ? "White" : "Black"
    return [line.eco, side, "\((line.moves.count + 1) / 2) moves"].compactMap { $0 }.joined(separator: " \u{00b7} ")
  }
}

/// A named line, its ideas, and Play or Add: `BookLineSheet`.
struct BookLineSheet: View {
  let line: BookLine
  let onPlay: ([String]) -> Void
  let onAdd: (BookLine) -> Void
  let onClose: () -> Void

  var body: some View {
    SheetFrame(title: line.name, onClose: onClose) {
      HStack(spacing: 6) {
        if let eco = line.eco { AnalysisChip(text: eco) }
        AnalysisChip(text: line.forColor == .w ? "White" : "Black", tone: line.forColor == .w ? .white : .black)
      }
      .padding(.bottom, 12)
      Text(line.summary).font(.system(size: 15)).foregroundStyle(Theme.text2)
      Spacer().frame(height: 8)
      SheetCard { MoveText(text: sansToMoveText(line.moves)) }
      if let ideas = line.ideas {
        AnalysisSectionHead(title: "Ideas")
        VStack(spacing: 0) {
          ForEach(Array(ideas.enumerated()), id: \.offset) { i, idea in
            if i > 0 { Rectangle().fill(.white.opacity(0.07)).frame(height: 1) }
            Text(idea).font(.system(size: 13)).foregroundStyle(Theme.text2)
              .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).padding(.horizontal, 16).padding(.vertical, 10)
          }
        }
        .background(RoundedRectangle(cornerRadius: 16).fill(Theme.surface2))
      }
      Spacer().frame(height: 16)
      HStack(spacing: 8) {
        WideButton(title: "Play", icon: "play") { onPlay(line.moves) }
        WideButton(title: "Add", icon: "plus", kind: .primary) { onAdd(line) }
      }
    }
  }
}

/// A famous game: its moves, and Replay from the board's move. The game sheet.
struct GameSheet: View {
  let game: ReferenceGame
  let onReplay: () -> Void
  let onClose: () -> Void

  var body: some View {
    SheetFrame(title: "\(game.white) \u{2013} \(game.black)", detents: [.medium], onClose: onClose) {
      HStack(spacing: 6) {
        AnalysisChip(text: game.result)
        Text([game.event, String(game.year)].compactMap { $0 }.joined(separator: " \u{00b7} "))
          .font(.system(size: 12)).foregroundStyle(Theme.text3).lineLimit(1)
      }
      .padding(.bottom, 12)
      SheetCard { MoveText(text: sansToMoveText(game.moves)) }
      Spacer().frame(height: 16)
      WideButton(title: "Replay", icon: "play", kind: .primary, action: onReplay)
    }
  }
}
