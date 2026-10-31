import Book
import ChessCore
import Model
import SwiftUI

/// Drill, a line at a time: `LineDrill.tsx`. The opponent's moves play
/// themselves, each of yours is asked, and the whole line takes one grade.
struct LineDrillView: View {
  @Environment(AppStore.self) private var store
  let tree: OpeningTree
  let onExit: () -> Void
  /// Autopilot's next round, offered once the sitting's lines are done.
  var onNext: (() -> Void)?
  @State private var model: LineDrillModel

  init(
    tree: OpeningTree, index: ReferenceIndex, store: AppStore, color: ChessCore.Color, openingId: String, lean: LineLean,
    prefs: DrillPrefs, count: Int? = nil, budget: Int? = nil, only: Set<String>? = nil, onExit: @escaping () -> Void,
    onNext: (() -> Void)? = nil
  ) {
    self.tree = tree
    self.onExit = onExit
    self.onNext = onNext
    _model = State(initialValue: LineDrillModel(
      color: color, openingId: openingId, lean: lean, prefs: prefs, count: count, budget: budget, only: only, store: store,
      tree: tree, index: index))
  }

  var body: some View {
    ZStack {
      if model.lines.line != nil { screen } else { empty }
      if let intro = model.intro, intro.stage == .announce {
        IntroCover(mode: intro.mode, trail: intro.trail).onTapGesture { intro.toBoard() }.transition(.opacity)
      }
    }
    .animation(.easeOut(duration: 0.3), value: model.intro?.stage == .announce)
    .onAppear { model.begin() }
    .onDisappear { model.stop() }
    .sheet(isPresented: $model.why) {
      if let played = model.lines.played, let expected = model.expected {
        WhySheet(fen: model.fen, side: model.color, played: played, expected: model.expectedMove, expectedSan: expected)
      }
    }
  }

  private var subtitle: String {
    store.catalog.map { selectionText(tree, $0, model.color == .w ? .w : .b, model.openingId) } ?? ""
  }

  private var empty: some View {
    VStack(spacing: 0) {
      PlayAppBar(title: "Drill lines", subtitle: subtitle, onClose: close) { Color.clear.frame(height: 1) }
      EmptyNote(title: "No lines to drill here", hint: "Build a line in Growth.")
      if let onNext {
        Button(action: onNext) { HStack(spacing: 8) { Text("Next round"); Icon(name: "next", size: 18) }.frame(maxWidth: .infinity) }
          .buttonStyle(PlayButtonStyle(kind: .primary, height: 56, radius: 16, font: 17)).padding(.horizontal, 16)
      }
      Spacer()
    }
  }

  private var screen: some View {
    let s = model.lines
    return VStack(spacing: 0) {
      DrillBar(title: "Drill lines", subtitle: subtitle, onClose: close) {
        if s.phase == .play && model.mine { ClockHud(clock: model.clock) }
        CountChip(text: model.count != nil ? "\(min(s.at + 1, s.batch.count))/\(s.batch.count)" : "\(s.finished)")
      }
      ScrollView {
        VStack(spacing: 0) {
          board
          if s.phase == .done { nextButton.padding(.top, 12) }
          Spacer().frame(height: 8)
          if !strip.isEmpty { MoveStrip(items: strip, cursor: s.ply, max: s.ply, arrows: false) { _ in } }
          Spacer().frame(height: 8)
          LineDrillPanel(model: model)
        }
        .padding(.horizontal, 16).padding(.top, 4).padding(.bottom, 28)
      }
    }
  }

  private var board: some View {
    let s = model.lines
    let lights: [String: SwiftUI.Color] = s.phase == .wrong
      ? squares(s.played, Theme.bad).merging(squares(model.expectedMove, Theme.good)) { $1 }
      : s.phase == .flash ? squares(s.played, Theme.good) : [:]
    return VStack(spacing: 0) {
      CapturedRow(fen: model.boardFen, orientation: model.color).padding(.bottom, 6)
      BoardView(
        fen: model.boardFen, orientation: model.color, interactive: s.phase == .play && model.mine && !model.held,
        highlights: lights, onMove: model.play)
        .dimmed(s.phase == .wrong)
        .overlay { if let intro = model.intro { IntroOverlay(intro: intro, moved: model.moved) } }
    }
  }

  private var nextButton: some View {
    let last = model.lastOfRound && onNext != nil
    return Button { if last { onNext?() } else { model.nextLine() } } label: {
      HStack(spacing: 8) { Text(last ? "Next round" : "Next line"); Icon(name: "next", size: 18) }.frame(maxWidth: .infinity)
    }
    .buttonStyle(PlayButtonStyle(kind: .primary, height: 52, radius: 14, font: 16))
  }

  private var strip: [StripItem] {
    guard let line = model.lines.line else { return [] }
    return line.sans.prefix(model.lines.ply).enumerated().map { i, san in
      StripItem(san: san, label: i % 2 == 0 ? "\(i / 2 + 1)." : nil, tone: yoursAt(model.color, i) ? .mine : .theirs)
    }
  }

  private func close() {
    model.stop()
    onExit()
  }
}

/// Under the board: whose move, a miss explained, or the line's grade.
struct LineDrillPanel: View {
  @Bindable var model: LineDrillModel

  var body: some View {
    let s = model.lines
    let misses = s.misses == 1 ? "1 miss" : "\(s.misses) misses"
    VStack(spacing: 0) {
      if s.phase == .play || s.phase == .flash {
        DrillPrompt(side: model.mine ? model.color : model.color.other, title: model.mine ? "Your move" : "Their move",
                    context: context + (s.misses > 0 ? " \u{00b7} \(misses)" : ""))
      }
      if s.phase == .wrong {
        HStack {
          DrillVerdict(tone: .no, text: "Off your prep")
          Spacer()
          ContinueButton(action: model.carryOnAfterMiss)
        }
        CompareCards(good: ("Playbook", model.expected ?? ""), bad: ("Played", s.played?.san ?? "")).padding(.top, 8)
        if model.prefs.explain { SoftButton(title: "Why?") { model.why = true }.padding(.top, 8) }
      }
      if s.phase == .done {
        DrillVerdict(tone: s.misses == 0 ? .ok : .warn, text: s.misses == 0 ? "Line finished clean" : "Line finished \u{00b7} \(misses)")
        if let graded = s.graded {
          Text("How did that line feel?").font(.system(size: 12)).foregroundStyle(Theme.text3).padding(.top, 18)
          GradeRow(selected: graded.grade, onPick: model.regrade).padding(.top, 8)
        }
      }
    }
  }

  private var context: String {
    let s = model.lines
    if model.count == nil && model.grouped {
      return "\(s.group > 1 && s.at == 0 ? "New group" : "Group \(s.group)") \u{00b7} line \(s.at + 1) of \(s.batch.count)"
    }
    return "Line \(model.count != nil ? "\(s.at + 1) of \(s.batch.count)" : "\(s.finished + 1)")"
  }
}
