import ChessCore
import Model
import SwiftUI

/// A game in play, and its end. `onNew` is back
/// to the setup for a new game; `onClose` is out of Play altogether.
struct PlayGameView: View {
  @Environment(AppStore.self) private var store
  @Bindable var game: PlayGame
  let tree: OpeningTree
  let onNew: () -> Void
  let onClose: () -> Void
  @State private var saving: [String]?

  var body: some View {
    ZStack {
      screen
      if game.intro == .announce {
        PlayIntroCover(trail: trail).onTapGesture { game.toBoard() }.transition(.opacity)
      }
    }
    .animation(.easeOut(duration: 0.3), value: game.intro)
    .onAppear { game.begin() }
    .onDisappear { game.stop() }
    .sheet(isPresented: Binding(get: { saving != nil }, set: { if !$0 { saving = nil } })) {
      SaveSheet(sans: saving ?? [], color: game.color, source: .play, onSaved: { _, _, _ in game.saved = true }) { saving = nil }
        .presentationDetents([.medium]).presentationBackground(Theme.background)
    }
  }

  private var trail: [String] {
    store.catalog.map { selectionTrail(tree, $0, game.selection.opening) } ?? []
  }

  private var subtitle: String {
    let side: ColorChoice = game.color == .w ? .w : .b
    let text = store.catalog.map { selectionText(tree, $0, side, game.selection.opening) } ?? ""
    return "\(game.level.name) \u{00b7} \(text)"
  }

  private var screen: some View {
    VStack(spacing: 0) {
      PlayAppBar(title: "Play", subtitle: subtitle, onClose: onClose) {
        Text("\(fullmoveNumber(game.fen))").font(.system(size: 13).monospacedDigit()).foregroundStyle(Theme.text2)
          .frame(maxWidth: .infinity, alignment: .trailing)
      }
      ScrollView {
        VStack(spacing: 0) {
          if game.prefs.showEval && store.state.settings.engineEnabled {
            PlayEvalBar(line: game.evalLine).padding(.bottom, 10)
          }
          board
          Spacer().frame(height: 16)
          if let over = game.over { ending(over) } else { prompt }
          if let offBook = game.offBook, game.over == nil { OffBookBanner(detail: offBook).padding(.top, 12) }
          if !game.moves.isEmpty {
            PlaySection(title: "Moves", aside: game.target.map { displayName($0.name) })
            MoveStrip(items: strip, cursor: game.moves.count, max: game.moves.count, arrows: false) { _ in }
          }
          if game.over == nil { actions.padding(.top, 12) }
          if game.over != nil && !game.moves.isEmpty { movetext }
        }
        .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 28)
      }
    }
  }

  private var board: some View {
    VStack(spacing: 0) {
      CapturedRow(fen: game.fen, orientation: game.color).padding(.bottom, 6)
      BoardView(
        fen: game.fen, orientation: game.color, interactive: game.myTurn && !game.held,
        lastMove: lastMoveOf(game.moves), onMove: game.play)
        .dimmed(game.over != nil)
        .overlay(alignment: .top) { if game.showsPill, let name = trail.last { IntroPill(name: name) } }
    }
  }

  private var prompt: some View {
    VStack(spacing: 3) {
      HStack(spacing: 8) {
        SideDot(side: fenTurn(game.fen))
        Text(game.thinking ? "Thinking\u{2026}" : game.myTurn ? "Your move" : "Their move")
          .font(.system(size: 17, weight: .bold)).foregroundStyle(Theme.text)
      }
      if game.status.check { Text("Check").font(.system(size: 13)).foregroundStyle(Theme.text3) }
    }
    .frame(maxWidth: .infinity).padding(.top, 6).padding(.bottom, 2)
  }

  @ViewBuilder private func ending(_ over: PlayGame.Over) -> some View {
    HStack {
      PlayVerdict(over: over)
      Spacer()
      Button(action: onNew) {
        HStack(spacing: 8) { Text("New game"); Icon(name: "next", size: 16) }
      }
      .buttonStyle(PlayButtonStyle(kind: .primary, height: 38, radius: 11, font: 14))
    }
    let line = openingLine(game.moves, game.color)
    if !game.saved && !line.isEmpty {
      Button { saving = line } label: {
        HStack(spacing: 8) { Icon(name: "plus", size: 18); Text("Save this opening") }.frame(maxWidth: .infinity)
      }
      .buttonStyle(PlayButtonStyle()).padding(.top, 12)
    }
  }

  private var actions: some View {
    HStack(spacing: 8) {
      if game.prefs.takeBacks {
        Button { game.takeBack() } label: { Text("Take back").frame(maxWidth: .infinity) }
          .buttonStyle(PlayButtonStyle(kind: .soft)).disabled(game.moves.count < 2)
      }
      Button { game.resign() } label: { Text("Resign").frame(maxWidth: .infinity) }
        .buttonStyle(PlayButtonStyle(kind: .soft))
    }
  }

  private var movetext: some View {
    VStack(alignment: .leading, spacing: 0) {
      PlaySection(title: "The game")
      Text(sansToMoveText(game.moves)).font(.system(size: 13, design: .monospaced)).lineSpacing(9).foregroundStyle(Theme.text2)
        .frame(maxWidth: .infinity, alignment: .leading).padding(16)
        .background(RoundedRectangle(cornerRadius: 16).fill(Theme.surface))
    }
  }

  private var strip: [StripItem] {
    game.moves.enumerated().map { i, san in
      StripItem(
        san: san, label: i % 2 == 0 ? "\(i / 2 + 1)." : nil,
        tone: (i % 2 == 0) == (game.color == .w) ? .mine : .theirs, current: i == game.moves.count - 1)
    }
  }
}
