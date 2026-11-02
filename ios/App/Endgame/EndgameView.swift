import ChessCore
import Engine
import Model
import SwiftUI

/// Endgame mode: the library by family, then one position at a time.
struct EndgameView: View {
  @Environment(AppStore.self) private var store
  let onExit: () -> Void
  @State private var game: EndgameGame?
  /// The positions left in a "Play due" sitting, after the one on the board.
  @State private var queue: [EndgameEntry] = []

  var body: some View {
    Group {
      if let game {
        EndgameRoundView(game: game, hasNext: !queue.isEmpty, onNext: next, onClose: { self.game = nil; queue = [] })
          .id(game.roundId)
      } else {
        EndgameHomeView(onPlay: { play([$0]) }, onPlayDue: { play($0) }, onExit: onExit)
      }
    }
  }

  private func play(_ entries: [EndgameEntry]) {
    guard let first = entries.first else { return }
    queue = Array(entries.dropFirst())
    game = EndgameGame(entry: first, store: store)
  }

  private func next() {
    guard let first = queue.first else {
      game = nil
      return
    }
    queue.removeFirst()
    game = EndgameGame(entry: first, store: store)
  }
}

/// The library: what is due, then each family with its tier and positions.
struct EndgameHomeView: View {
  @Environment(AppStore.self) private var store
  let onPlay: (EndgameEntry) -> Void
  let onPlayDue: ([EndgameEntry]) -> Void
  let onExit: () -> Void

  var body: some View {
    let record = store.state.endgames
    let due = record.due(Env.now())
    VStack(spacing: 0) {
      PlayAppBar(title: "Endgames", subtitle: nil, onClose: onExit) { EmptyView() }
      ScrollView {
        VStack(spacing: 12) {
          Button {
            if !due.isEmpty {
              onPlayDue(due)
            } else if let next = record.next(Env.now()) {
              onPlay(next)
            }
          } label: {
            Text(due.isEmpty ? "Play the next one" : "Play \(due.count) due").frame(maxWidth: .infinity)
          }
          .buttonStyle(PlayButtonStyle(kind: .accent, block: true))
          .disabled(due.isEmpty && record.next(Env.now()) == nil)
          ForEach(ENDGAME_FAMILIES, id: \.id) { family in
            let rows = record.entries.filter { $0.family == family.id }
            if !rows.isEmpty { section(family, rows, record) }
          }
        }
        .padding(.horizontal, 16).padding(.top, 4).padding(.bottom, 28)
      }
    }
  }

  private func section(_ family: EndgameFamily, _ rows: [EndgameEntry], _ record: EndgameRecord) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(spacing: 12) {
        Text(family.name).font(.system(size: 17, weight: .heavy)).foregroundStyle(Theme.text)
        Spacer()
        TierBar(rating: record.ratings[family.id] ?? 0, rated: record.rated[family.id] ?? 0).frame(width: 110)
      }
      .padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 6)
      ForEach(rows, id: \.id) { entry in
        Button { onPlay(entry) } label: {
          HStack(spacing: 10) {
            SideDot(side: entry.fen.map(fenTurn) ?? .w)
            Text(entry.name).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.text).lineLimit(1)
            Spacer()
            if let card = record.cards[entry.id], card.due <= Env.now() {
              Text("Due").font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.accent)
            }
            Text(entry.goal.label).font(.system(size: 13, weight: .semibold))
              .foregroundStyle(entry.goal == .win ? Theme.good : Theme.text2)
            Icon(name: "chevron", size: 16).foregroundStyle(Theme.text3)
          }
          .padding(.horizontal, 14).frame(minHeight: 46)
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
      }
    }
    .padding(.bottom, 6)
    .background(RoundedRectangle(cornerRadius: 16).fill(Theme.surface))
  }
}

/// One position on the board: its intro card first time round, the goal card,
/// the lens bar, and how it ended.
struct EndgameRoundView: View {
  @Environment(AppStore.self) private var store
  @Bindable var game: EndgameGame
  let hasNext: Bool
  let onNext: () -> Void
  let onClose: () -> Void
  @State private var lens: LensKind?

  var body: some View {
    ZStack {
      screen
      if game.phase == .intro, let intro = game.entry.intro {
        EndgameIntroCard(name: game.entry.name, intro: intro, fen: game.start, color: game.color) { game.toBoard() }
          .transition(.opacity)
      }
    }
    .animation(.easeOut(duration: 0.3), value: game.phase)
    .onAppear { if game.phase == .playing { game.engineTurn() } }
    .onChange(of: game.phase) { if game.phase == .playing { game.engineTurn() } }
    .onDisappear { game.stop() }
  }

  private var screen: some View {
    VStack(spacing: 0) {
      PlayAppBar(title: game.entry.name, subtitle: game.entry.goal.label, onClose: onClose) {
        if game.entry.intro != nil && game.moves.isEmpty && game.phase == .playing {
          Button { game.replayIntro() } label: { Icon(name: "pages", size: 20).foregroundStyle(Theme.text2) }
            .buttonStyle(.plain)
        }
      }
      ScrollView {
        VStack(spacing: 0) {
          Text("ENDGAME").font(.system(size: 11, weight: .bold)).tracking(0.8).foregroundStyle(Theme.text2)
            .frame(maxWidth: .infinity, alignment: .leading).padding(.bottom, 6)
          CapturedRow(fen: game.fen, orientation: game.color)
            .opacity(lens == .eval ? 0 : 1)
            .overlay { if lens == .eval { EvalLensBar(cp: game.evalCp, result: result) } }
            .padding(.bottom, 6)
          BoardView(
            fen: game.fen, orientation: game.color, interactive: game.myTurn, lastMove: game.lastMove,
            highlights: highlights, marks: marks, onMove: game.play)
            .dimmed(game.phase == .over)
            .overlay(alignment: .top) {
              if let note = game.note {
                Text(note).font(.system(size: 14, weight: .bold)).foregroundStyle(Theme.bad)
                  .padding(.horizontal, 14).padding(.vertical, 7).background(Capsule().fill(Theme.surface))
                  .padding(.top, 10)
              }
            }
          LensBar(held: $lens, lenses: LENSES, enabled: game.phase == .playing)
          if let lens, lens != .eval { LensLegend(kind: lens, endgame: true) }
          if let outcome = game.outcome { ending(outcome) } else { goal }
          if game.phase == .playing {
            Button { game.resign() } label: { Text("Give up").frame(maxWidth: .infinity) }
              .buttonStyle(PlayButtonStyle(kind: .soft, block: true)).padding(.top, 12)
          }
        }
        .padding(.horizontal, 16).padding(.top, 4).padding(.bottom, 28)
      }
    }
  }

  private var marks: LensMarks? {
    guard let lens, lens != .eval, game.phase == .playing else { return nil }
    return heldLens(lens, game.fen, game.color)
  }

  /// Where you missed a mate, the move that had it, in red.
  private var highlights: [String: SwiftUI.Color] {
    guard let best = game.missedBest else { return [:] }
    return [best.from: Theme.bad.opacity(0.45), best.to: Theme.bad.opacity(0.45)]
  }

  private var result: EndResult? {
    exactResult(game.fen, for: game.color) ?? game.evalCp.map { resultOf(game.color, $0) }
  }

  private var goal: some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack {
        Text(game.entry.mission.title).font(.system(size: 11, weight: .heavy)).tracking(0.8).foregroundStyle(Theme.accent)
        Spacer()
        if case .holdFor(let n) = game.entry.mission {
          Text("\(max(0, n - game.yourMoves)) TO GO").font(.system(size: 11, weight: .heavy)).tracking(0.8).foregroundStyle(Theme.text2)
        }
      }
      Text(game.entry.mission.text).font(.system(size: 16, weight: .bold)).foregroundStyle(Theme.text)
      Text(game.thinking ? "Thinking\u{2026}" : game.myTurn ? "Your move" : "Their move")
        .font(.system(size: 13)).foregroundStyle(Theme.text2)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.horizontal, 14).padding(.vertical, 12)
    .background(RoundedRectangle(cornerRadius: 12).fill(Theme.surface))
    .padding(.top, 12)
  }

  /// What an outcome says, whether the goal was met, and whether the mission was.
  private func parts(_ outcome: EndgameOutcome) -> (text: String, good: Bool, mission: Bool) {
    switch outcome {
    case .success(let text, let mission): return (text, true, mission)
    case .failure(let text): return (text, false, false)
    }
  }

  private func ending(_ outcome: EndgameOutcome) -> some View {
    let (text, good, mission) = parts(outcome)
    return VStack(alignment: .leading, spacing: 10) {
      Text(text).font(.system(size: 21, weight: .heavy)).foregroundStyle(good ? Theme.good : Theme.bad)
      if good {
        Text(mission ? "\(game.entry.mission.text): done" : "\(game.entry.mission.text): missed")
          .font(.system(size: 14)).foregroundStyle(Theme.text2)
      }
      Text("\(game.entry.family == "games" ? "From your games" : familyName) \u{2014} \(store.state.endgames.rank(game.entry.family).heldLabel)")
        .font(.system(size: 13)).foregroundStyle(Theme.text3)
      HStack(spacing: 8) {
        Button(action: onClose) { Text("Library").frame(maxWidth: .infinity) }
          .buttonStyle(PlayButtonStyle(kind: .soft, block: true))
        Button(action: onNext) { Text(hasNext ? "Next" : "Done").frame(maxWidth: .infinity) }
          .buttonStyle(PlayButtonStyle(kind: .primary, block: true))
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.top, 16)
  }

  private var familyName: String { ENDGAME_FAMILIES.first { $0.id == game.entry.family }?.name ?? "" }
}

/// The card before a position's first round: its name, the idea, and the board behind.
struct EndgameIntroCard: View {
  let name: String
  let intro: EndgameIntro
  let fen: String
  let color: ChessCore.Color
  let onPlay: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      Text(name.uppercased()).font(.system(size: 12, weight: .heavy)).tracking(0.9).foregroundStyle(Theme.accent)
      Text(intro.title).font(.system(size: 26, weight: .heavy)).foregroundStyle(Theme.text)
      BoardView(fen: fen, orientation: color, interactive: false, lastMove: nil, onMove: { _ in })
        .allowsHitTesting(false)
      ForEach(intro.lines, id: \.self) { line in
        Text(line).font(.system(size: 16)).foregroundStyle(Theme.text).fixedSize(horizontal: false, vertical: true)
      }
      Spacer(minLength: 0)
      Button(action: onPlay) { Text("Play it").frame(maxWidth: .infinity) }
        .buttonStyle(PlayButtonStyle(kind: .accent, block: true))
    }
    .padding(20)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .background(Theme.background.ignoresSafeArea())
  }
}
