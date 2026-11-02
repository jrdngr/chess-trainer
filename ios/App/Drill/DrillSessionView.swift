import Book
import ChessCore
import Model
import SwiftUI

/// Drill positions. The Playbook opens it directly with
/// a branch's items (`branchItems(rep, nodeId).prefix(40)`) and a title.
struct DrillSessionView: View {
  @Environment(AppStore.self) private var store
  let tree: OpeningTree
  let index: ReferenceIndex
  let onExit: () -> Void
  @State private var model: DrillSessionModel

  /// `prefs` nil plays with Drill's defaults, as a sitting from the Playbook does.
  init(
    tree: OpeningTree, index: ReferenceIndex, store: AppStore, items: [TrainingItem], mode: SessionMode = .branch,
    title: String, prefs: DrillPrefs? = nil, openingId: String? = nil, onExit: @escaping () -> Void
  ) {
    self.tree = tree
    self.index = index
    self.onExit = onExit
    _model = State(initialValue: DrillSessionModel(
      items: items, mode: mode, title: title, prefs: prefs ?? DEFAULT_DRILL, openingId: openingId, store: store, tree: tree))
  }

  var body: some View {
    ZStack {
      if model.item != nil { screen } else { empty }
      if let intro = model.intro, intro.stage == .announce {
        IntroCover(mode: intro.mode, trail: intro.trail).onTapGesture { intro.toBoard() }.transition(.opacity)
      }
    }
    .animation(.easeOut(duration: 0.3), value: model.intro?.stage == .announce)
    .onAppear { model.begin() }
    .onDisappear { model.stop() }
    .sheet(isPresented: $model.why) {
      if let item = model.item, let played = model.drill.played {
        WhySheet(fen: item.fen, side: model.side, played: played, expected: model.expectedMove, expectedSan: model.preferred?.san)
      }
    }
    .sheet(isPresented: $model.explore) { exploreSheet }
  }

  private var subtitle: String {
    store.catalog.map { selectionText(tree, $0, model.side == .w ? .w : .b, model.openingId) } ?? ""
  }

  private var empty: some View {
    VStack(spacing: 0) {
      PlayAppBar(title: model.title, subtitle: subtitle, onClose: close) { Color.clear.frame(height: 1) }
      EmptyNote(title: "Nothing to drill here", hint: "Add a line in the Playbook.")
      Spacer()
    }
  }

  private var screen: some View {
    VStack(spacing: 0) {
      DrillBar(title: model.title, subtitle: subtitle, onClose: close) {
        if model.drill.phase == .ask { ClockHud(clock: model.clock) }
        CountChip(text: "\(model.drill.stats.answered)")
      }
      ScrollView {
        VStack(spacing: 0) {
          board
          if let intro = model.intro, intro.replaying {
            Text(sansToMoveText(Array(intro.path.prefix(intro.ply)))).font(.system(size: 13)).foregroundStyle(Theme.text2)
              .frame(minHeight: 18).padding(.top, 8)
          }
          Spacer().frame(height: 16)
          if model.drill.phase == .ask { DrillAskPanel(model: model, close: close) }
          if model.drill.phase == .wrong { DrillWrongPanel(model: model) }
        }
        .padding(.horizontal, 16).padding(.top, 4).padding(.bottom, 28)
      }
    }
  }

  private var board: some View {
    let phase = model.drill.phase
    let played = model.drill.played
    let lights: [String: SwiftUI.Color] = phase == .wrong
      ? squares(played, Theme.bad).merging(squares(model.expectedMove, Theme.good)) { $1 }
      : phase == .flash ? squares(played, Theme.good) : [:]
    return VStack(spacing: 0) {
      CapturedRow(fen: model.boardFen, orientation: model.side).padding(.bottom, 6)
      BoardView(
        fen: model.intro?.fen ?? model.boardFen, orientation: model.side, interactive: phase == .ask && !model.held,
        lastMove: model.intro?.lastMove, highlights: model.held ? [:] : lights, onMove: model.play)
        .dimmed(phase == .wrong)
        .overlay { if let intro = model.intro { IntroOverlay(intro: intro, moved: model.drill.stats.answered > 0) } }
    }
  }

  private var exploreSheet: some View {
    let item = model.item
    return ScrollView {
      VStack(alignment: .leading, spacing: 0) {
        SheetHead(title: "Reference", moves: item.map { sansToMoveText($0.pathSans) }.flatMap { $0.isEmpty ? "Start" : $0 })
        if let item {
          ExplorerPanel(index: index, fen: item.fen, path: item.pathSans, inRepertoire: item.expected.map(\.san)) { _ in model.explore = false }
        }
      }
      .padding(20)
    }
    .presentationDetents([.medium, .large]).presentationBackground(Theme.background)
  }

  private func close() {
    model.stop()
    onExit()
  }
}

/// The centred app bar with a count on the right: `AppBar` with actions.
struct DrillBar<Trailing: View>: View {
  var title: String
  var subtitle: String
  var onClose: () -> Void
  @ViewBuilder var trailing: Trailing

  var body: some View {
    ZStack {
      VStack(spacing: 1) {
        Text(title).font(.system(size: 17, weight: .bold)).foregroundStyle(Theme.text)
        Text(subtitle).font(.system(size: 13)).foregroundStyle(Theme.text2)
      }
      .lineLimit(1).padding(.horizontal, 84)
      HStack {
        IconButton(icon: "close", action: onClose)
        Spacer()
        HStack(spacing: 6) { trailing }
      }
    }
    .padding(.horizontal, 20).padding(.top, 10).padding(.bottom, 10).frame(minHeight: 56)
  }
}
