import ChessCore
import Engine
import Game
import Model
import Shared
import SwiftUI

/// The end of a run. Final position and End of prep to switch
/// between, the board, Grow this line, Analyze and Back Home (Next run in
/// Run and Middlegame), then what
/// the run came to and the rating it moved. A Run run you set up
/// (no Play round) adds its own parts: `RunEndParts`. A Middlegame
/// run names its start Handoff, scores in points and offers Same line.
struct EndView: View {
  let model: RunModel
  let finish: Finish
  let onNext: () -> Void
  let onAnalyze: () -> Void
  let onExit: () -> Void
  /// Back to Run's setup; nil when Play set the run up.
  let onChangeOptions: (() -> Void)?
  /// Middlegame's: the same line played out again.
  let onSameLine: (() -> Void)?
  @Environment(AppStore.self) private var store
  @Environment(\.openTidy) private var openTidy
  /// How many of the run's moves are on the board.
  @State private var cursor: Int
  /// Where the rating card is: playing over the board (once the verdict clears), fading on its way down, or in its place.
  @State private var card: RatingStage = .play
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var lens: LensKind?
  @State private var evalLine: EngineLine?
  /// The verdict over the board as the screen opens; a blunder was shown on the board already.
  @State private var flashing: Bool

  init(model: RunModel, finish: Finish, onNext: @escaping () -> Void,
       onAnalyze: @escaping () -> Void, onExit: @escaping () -> Void, onChangeOptions: (() -> Void)? = nil,
       onSameLine: (() -> Void)? = nil) {
    self.model = model
    self.finish = finish
    self.onNext = onNext
    self.onAnalyze = onAnalyze
    self.onExit = onExit
    self.onChangeOptions = onChangeOptions
    self.onSameLine = onSameLine
    _cursor = State(initialValue: finish.ended.run.played.count)
    var blunder = false
    if case .blunder = finish.how { blunder = true }
    _flashing = State(initialValue: !blunder && !model.endSeen)
    _card = State(initialValue: model.endSeen ? .placed(arriving: false) : .play)
  }

  /// Run opened from Home, not Play's round.
  private var standalone: Bool { model.round == nil }
  /// A Middlegame run, begun at its handoff.
  private var middlegame: Bool { model.handoff != nil }

  private var run: Run { finish.ended.run }
  private var last: Int { run.played.count }
  private var fens: [String] { walkSan(run.played).fens }
  private var shownFen: String { fens[min(cursor, last)] }
  private var blunder: (played: String, best: String?, lost: Double)? {
    if case .blunder(let played, let best, let lost, _, _) = finish.how { return (played, best, lost) }
    return nil
  }
  private var onBlunder: Bool { blunder != nil && cursor == last }
  /// Where your prep ended, when the run went past it.
  private var prepAt: Int? {
    let ply = model.session.prepEnd?.count ?? finish.ended.misses.first?.ply
    return ply.flatMap { $0 < last ? $0 : nil }
  }
  /// On the blunder, the position it left, so the bar shows what it cost.
  private var weighed: String { onBlunder ? (applySan(run.fen, blunder!.played)?.after ?? shownFen) : shownFen }

  private func seek(_ n: Int) { cursor = max(0, min(last, n)) }

  /// The misses Tidy has a switch for; only when there is a Tidy to go to.
  private var hints: [Int: TidyFind] {
    guard openTidy != nil, let index = store.index else { return [:] }
    let rep = store.state.playbookList.first { $0.color == run.color }
    return tidyHints(finish.ended.misses, rep, index, model.round != nil ? AUTO_GROWTH : store.state.settings.growth)
  }

  var body: some View {
    VStack(spacing: 0) {
      if standalone {
        RunBar(title: "Middlegame", subtitle: openingName(model.tree, run.enteredIn ?? run.openingId), onClose: onExit) {
          EmptyView()
        }
      }
      scroll.modifier(RunDebugScroll())
    }
    .onAppear {
      if reduceMotion { card = .placed(arriving: false) }
      model.endSeen = true
    }
    .task(id: card) {
      guard card == .leave else { return }
      try? await Task.sleep(for: .seconds(0.32))
      card = .placed(arriving: true)
    }
    .task {
      guard flashing else { return }
      try? await Task.sleep(for: .seconds(1.5))
      withAnimation { flashing = false }
    }
    .task(id: weighed) {
      evalLine = nil
      let fen = weighed
      let snap = await HintEngine.shared.analyse(fen, EngineLimits(depth: 16, multiPv: 1))
      if !Task.isCancelled && fen == weighed { evalLine = snap.lines.first }
    }
  }

  private var scroll: some View {
    let missAt = finish.ended.misses.first { $0.ply == cursor }
    return ScrollView {
      VStack(spacing: 0) {
        if !standalone { header.padding(.bottom, 14) }
        if let prepAt {
          SegmentedControl(
            value: Binding(get: { cursor == prepAt ? 0 : cursor == last ? 1 : -1 }, set: { seek($0 == 0 ? prepAt : last) }),
            options: [(0, middlegame ? "Handoff" : "End of prep"), (1, "Final position")]
          )
          .padding(.bottom, 10)
        }
        evalBar.padding(.bottom, 10)
        if let caption = marks?.caption {
          Text(caption).font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.text).frame(minHeight: 22).padding(.bottom, 6)
        } else {
          CapturedRow(fen: shownFen, orientation: run.color).padding(.bottom, 6)
        }
        BoardView(
          fen: shownFen, orientation: run.color, interactive: false,
          lastMove: onBlunder || missAt != nil ? nil : lastMoveOf(Array(run.played.prefix(cursor))),
          highlights: highlights(missAt), marks: marks, onMove: { _ in })
          .clearsLens($lens)
          .overlay {
            if !flashing, let moment, card == .play || card == .leave {
              RatingOverBoard(moment: moment, leaving: card == .leave) { if card == .play { card = .leave } }
            }
          }
        // The verdict fades out before the lenses fade in, so the two never show through each other.
        LensBar(held: $lens)
          .opacity(flashing ? 0 : 1).allowsHitTesting(!flashing)
          .animation(.easeIn(duration: 0.2).delay(0.25), value: flashing)
          .overlay(alignment: .top) {
            if flashing {
              EndVerdict(how: finish.how, plies: last).padding(.top, 8).transition(.opacity.animation(.easeOut(duration: 0.2)))
            }
          }
          // The verdict runs past the lenses' row: over the buttons under it, not under them.
          .zIndex(1)
        if let lens {
          LensLegend(kind: lens, endgame: isEndgame(shownFen), safety: marks?.safety).clearsLens($lens)
        } else {
          below
        }
      }
      .padding()
    }
  }

  /// Analyze and Back Home (Next run outside Play), the moves, and what the run came to.
  private var below: some View {
    VStack(spacing: 14) {
      HStack(spacing: 8) {
        if blunder != nil || isEnded || middlegame {
          Button(action: onAnalyze) {
            Label("Analyze", systemImage: "magnifyingglass")
          }
          .buttonStyle(PlayButtonStyle(height: 52, block: true, inset: 8))
        }
        if let onSameLine {
          Button(action: onSameLine) {
            Label("Same line", systemImage: "arrow.counterclockwise")
          }
          .buttonStyle(PlayButtonStyle(height: 52, block: true, inset: 8))
        }
        Button(action: onNext) {
          if standalone {
            HStack(spacing: 6) { Text("Next run"); Icon(name: "next", size: 18) }
          } else {
            HStack(spacing: 6) { Icon(name: "house", size: 18); Text("Back Home") }
          }
        }
        .buttonStyle(PlayButtonStyle(kind: .primary, height: 52, block: true, inset: 8))
      }
      // Three buttons share a phone's width: each label stays on one line.
      .labelStyle(TightLabelStyle())
      .lineLimit(1)
      .minimumScaleFactor(0.8)
      MoveStrip(items: strip, cursor: cursor, max: last, onSeek: seek)
      ratingCard
      RatingsList(items: moved).padding(.top, 10)
      if standalone {
        RunSummary(
          finish: finish, prefs: model.prefs, scoredInPoints: model.scoredInPoints, before: model.before ?? RunRecord(),
          pointsOnly: middlegame)
      } else {
        summary
      }
      if let blunder { compare(blunder) }
      Group {
        VStack(spacing: 0) {
          MissedPrepList(misses: finish.ended.misses, hints: hints, onTidy: openTidy, onSeek: seek)
          if let handoff = model.handoff {
            MovesSurvivedList(
              tree: model.tree, line: Array(handoff.line.prefix(handoff.prep)), opening: playedNode.id,
              record: store.state.middlegame, moves: finish.ended.extras.points, title: "Middlegame points")
          } else {
            MovesSurvivedList(
              tree: model.tree, line: run.played, opening: playedNode.id, record: store.state.runRecord,
              moves: finish.ended.moves)
          }
          RunEndActions(played: sansToMoveText(run.played + (blunder.map { [$0.played] } ?? [])), onChangeOptions: onChangeOptions)
        }
        .padding(.top, -14)
      }
    }
    .padding(.top, 12)
  }

  private var evalBar: some View {
    HStack(spacing: 8) {
      GeometryReader { geo in
        Capsule().fill(Theme.surface3)
          .overlay(alignment: .leading) {
            Rectangle().fill(Color(hex: 0xf5f5f7)).frame(width: geo.size.width * winFraction(evalLine))
              .animation(.easeOut(duration: 0.35), value: winFraction(evalLine))
          }
          .clipShape(Capsule())
      }
      .frame(height: 6)
      Text(evalLine.map(formatScore) ?? "\u{2014}").font(.footnote.monospacedDigit()).foregroundStyle(Theme.text2)
        .frame(minWidth: 48, alignment: .trailing)
    }
  }

  /// What a held lens draws over the shown position.
  private var marks: LensMarks? {
    guard let lens else { return nil }
    return heldLens(lens, shownFen, run.color, cursor > 0 ? fens[cursor - 1] : nil)
  }

  /// The run's moves, a miss on the position it was asked in, then the blunder beside the engine's move.
  private var strip: [StripItem] {
    let label = { (ply: Int) in ply % 2 == 0 ? "\(ply / 2 + 1)." : nil }
    let mine = { (ply: Int) in (ply % 2 == 0) == (run.color == .w) }
    let missed = Set(finish.ended.misses.map(\.ply))
    // Common moves are marked from where your line ended.
    let common = store.index.map { commonPlies($0, run.played, from: model.session.prepEnd?.count ?? finish.ended.misses.first?.ply ?? last) } ?? []
    var items = run.played.enumerated().map { ply, san in
      StripItem(
        san: san, label: label(ply),
        tone: ply < run.opened ? .ghost : missed.contains(ply) ? .bad : mine(ply) ? .mine : .theirs,
        current: missed.contains(ply) ? cursor == ply : cursor == ply + 1 && !missed.contains(cursor) && !onBlunder,
        seek: missed.contains(ply) ? ply : ply + 1, common: common.contains(ply))
    }
    if let blunder {
      items.append(StripItem(san: blunder.played, label: label(last), tone: .bad, current: onBlunder, seek: last))
      if let best = blunder.best { items.append(StripItem(san: best, label: label(last), tone: .good, seek: last)) }
    }
    return items
  }

  /// The ratings this run moved that the end screen names: the opening it was
  /// played in and that opening's family, not every opening above it. The
  /// run's own opening plays on its own card instead.
  private var moved: [RatingsList.Item] {
    let node = deepestNodeWithin(model.tree, nodeById(model.tree, run.openingId), run.played)
    let named = Set([node.id] + (familyOf(model.tree, node).map { [$0.id] } ?? []))
    return model.ratings.changes
      .filter { JSRound($0.delta) != 0 }
      .filter { named.contains($0.id) && !(moment != nil && $0.id == model.openingId) }
      .map { RatingsList.Item(id: $0.id, name: nodeById(model.tree, $0.id).name, delta: $0.delta, after: $0.after) }
  }

  /// The engine's move beside the one that ended the run.
  private func compare(_ blunder: (played: String, best: String?, lost: Double)) -> some View {
    HStack(spacing: 10) {
      side("Engine", blunder.best ?? "\u{2014}", Theme.good)
      side("You played \u{00b7} \u{2212}\(JS.toFixed(blunder.lost / 100, 2))", blunder.played, Theme.bad)
    }
    .padding(.top, 8)
  }

  private func side(_ key: String, _ value: String, _ color: SwiftUI.Color) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(key).font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.text3)
      Text(value).font(.system(size: 22, weight: .heavy)).foregroundStyle(color)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.horizontal, 14).padding(.vertical, 12)
    .background(RoundedRectangle(cornerRadius: 18).fill(Theme.surface))
  }

  /// Run's: the blunder beside the engine's move, or a miss beside your prep, where they were played.
  private func highlights(_ missAt: Miss?) -> [String: SwiftUI.Color] {
    if onBlunder, let blunder { return endHighlights(run.fen, played: blunder.played, right: blunder.best) }
    if let missAt { return endHighlights(missAt.fen, played: missAt.played, right: missAt.expected) }
    return [:]
  }

  private var isEnded: Bool {
    if case .ended = finish.how { return true }
    return false
  }

  private var header: some View {
    HStack {
      Button(action: onExit) {
        Image(systemName: "xmark").font(.headline).frame(width: 38, height: 38).background(Circle().fill(Theme.surface))
      }
      .foregroundStyle(Theme.text).buttonStyle(.plain)
      Spacer()
      Text(openingName(model.tree, playedNode.id)).font(.headline).foregroundStyle(Theme.text).lineLimit(1)
      Spacer()
      // Balances the close button, so the title sits centered.
      Color.clear.frame(width: 38, height: 38)
    }
  }

  /// The opening the run was played in: the one picked, or under Any Opening the family the game reached.
  private var playedNode: OpeningNode {
    let picked = nodeById(model.tree, model.openingId)
    if picked.depth > 0 { return picked }
    let deepest = deepestNodeWithin(model.tree, picked, run.played)
    return familyOf(model.tree, deepest) ?? deepest
  }

  /// What it scored and how it ended, then prep, speed and misses as labeled numbers.
  /// A run that never left its prep leads with the prep, not with a score of nothing.
  private var summary: some View {
    let state = finish.ended
    let answers = model.session.answers
    let found = answers.filter(\.correct).count
    let times = model.session.prepTimes
    let scored = state.moves > 0 || state.extras.points > 0
    let title = endingTitle(finish.how, state.run.played.count)
    return VStack(spacing: 6) {
      if scored {
        Text("\(state.extras.points) point\(state.extras.points == 1 ? "" : "s")").font(.largeTitle.bold()).foregroundStyle(Theme.text)
        Text(title).font(.subheadline).foregroundStyle(isBad ? Theme.bad : Theme.text2)
      } else if !answers.isEmpty && found == answers.count {
        Text("Prep complete").font(.title.bold()).foregroundStyle(Theme.text)
        Text(title).font(.subheadline).foregroundStyle(Theme.text2)
      } else {
        Text(title).font(.title2.bold()).foregroundStyle(isBad ? Theme.bad : Theme.text)
      }
      if !answers.isEmpty {
        HStack(alignment: .top, spacing: 0) {
          stat("\(found) of \(answers.count)", "prep")
          if !times.isEmpty { stat(secondsText(times.reduce(0, +) / Double(times.count)), "a move") }
          stat("\(state.misses.count)", state.misses.count == 1 ? "miss" : "misses", state.misses.isEmpty ? Theme.text : Theme.bad)
        }
        .padding(.top, 10)
      }
    }
    .frame(maxWidth: .infinity).padding(.vertical, 18)
    .background(RoundedRectangle(cornerRadius: 18).fill(Theme.surface))
  }

  private func stat(_ value: String, _ label: String, _ color: SwiftUI.Color = Theme.text) -> some View {
    VStack(spacing: 2) {
      Text(value).font(.system(size: 17, weight: .semibold).monospacedDigit()).foregroundStyle(color)
      Text(label).font(.system(size: 12)).foregroundStyle(Theme.text3)
    }
    .frame(maxWidth: .infinity)
  }

  private var isBad: Bool {
    if case .blunder = finish.how { return true }
    if case .lost = finish.how { return true }
    return false
  }

  /// The opening's own rating, as this run moved it.
  private var moment: RatingMoment? { model.ratingMoment }

  @ViewBuilder private var ratingCard: some View {
    if let moment, case .placed(let arriving) = card {
      RestingRatingCard(moment: moment, arriving: arriving).padding(.top, 12)
    }
  }
}

/// The rating card's place on the end screen.
enum RatingStage: Equatable {
  case play, leave
  case placed(arriving: Bool)
}

/// Icon and title close together, so a label fits a third of the row.
private struct TightLabelStyle: LabelStyle {
  func makeBody(configuration: Configuration) -> some View {
    HStack(spacing: 6) { configuration.icon; configuration.title }
  }
}
