import ChessCore
import Engine
import Model
import Shared
import SwiftUI

/// The end of a run: `End.tsx`. Final position and End of prep to switch
/// between, the board, Grow this line, Analyze and Next round, then what
/// the run came to and the rating it moved. A Survival run you set up
/// (no Autopilot round) adds its own parts: `SurvivalEndParts`.
struct EndView: View {
  let model: RunModel
  let finish: Finish
  let onNext: () -> Void
  let onGrow: (GrowOffer) -> Void
  let onAnalyze: () -> Void
  let onExit: () -> Void
  /// Back to Survival's setup; nil when Autopilot set the run up.
  let onChangeOptions: (() -> Void)?
  @Environment(AppStore.self) private var store
  /// How many of the run's moves are on the board.
  @State private var cursor: Int
  /// The rating change has played over the board and gone down to its place.
  @State private var played = false
  @State private var lens: LensKind?
  @State private var evalLine: EngineLine?
  /// The verdict over the board as the screen opens; a blunder was shown on the board already.
  @State private var flashing: Bool

  init(model: RunModel, finish: Finish, onNext: @escaping () -> Void, onGrow: @escaping (GrowOffer) -> Void,
       onAnalyze: @escaping () -> Void, onExit: @escaping () -> Void, onChangeOptions: (() -> Void)? = nil) {
    self.model = model
    self.finish = finish
    self.onNext = onNext
    self.onGrow = onGrow
    self.onAnalyze = onAnalyze
    self.onExit = onExit
    self.onChangeOptions = onChangeOptions
    _cursor = State(initialValue: finish.ended.run.played.count)
    var blunder = false
    if case .blunder = finish.how { blunder = true }
    _flashing = State(initialValue: model.round == nil && !blunder)
  }

  /// Survival opened from Home, not Autopilot's round.
  private var survival: Bool { model.round == nil }

  private var run: Run { finish.ended.run }
  private var last: Int { run.played.count }
  private var fens: [String] { walkSan(run.played).fens }
  private var shownFen: String { fens[min(cursor, last)] }
  private var blunder: (played: String, best: String?, lost: Double)? {
    if case .blunder(let played, let best, let lost, _) = finish.how { return (played, best, lost) }
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

  var body: some View {
    VStack(spacing: 0) {
      if survival {
        SurvivalBar(subtitle: runSubtitle(store, run.color, run.enteredIn ?? run.openingId), onClose: onExit) {
          CountChip(value: finish.ended.moves)
        }
      }
      scroll.modifier(SurvivalDebugScroll())
    }
    .task {
      guard flashing else { return }
      try? await Task.sleep(for: .seconds(2))
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
        if !survival { header.padding(.bottom, 14) }
        if let prepAt {
          SegmentedControl(
            value: Binding(get: { cursor == prepAt ? 0 : cursor == last ? 1 : -1 }, set: { seek($0 == 0 ? prepAt : last) }),
            options: [(0, "End of prep"), (1, "Final position")]
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
          highlights: survival ? highlights(missAt) : [:], marks: marks, onMove: { _ in })
          .overlay {
            if flashing {
              EndVerdict(how: finish.how, plies: last).onTapGesture { flashing = false }.transition(.opacity)
            } else if let moment, !played {
              ZStack {
                Theme.background.opacity(0.6)
                RatingPlayback(moment: moment) { withAnimation { played = true } }
              }
              .transition(.opacity)
            }
          }
        LensBar(held: $lens)
        if let lens {
          LensLegend(kind: lens)
        } else {
          below
        }
      }
      .padding()
    }
  }

  /// Grow, Analyze and Next round, the moves, and what the run came to.
  private var below: some View {
    VStack(spacing: 14) {
      if let offer = model.offer {
        if offer.kind == "opening", let text = offer.text {
          Text(text).font(.subheadline).foregroundStyle(Theme.text).frame(maxWidth: .infinity, alignment: .leading)
        }
        Button { onGrow(offer) } label: {
          Label(offer.kind == "opening" ? "Grow this opening" : "Grow this line", systemImage: "plus")
            .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 14)
        }
        .background(RoundedRectangle(cornerRadius: 18).fill(Theme.accent)).foregroundStyle(Theme.accentInk)
      }
      HStack(spacing: 12) {
        if blunder != nil || isEnded {
          Button(action: onAnalyze) {
            Label("Analyze", systemImage: "magnifyingglass").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 14)
          }
          .background(RoundedRectangle(cornerRadius: 18).fill(Theme.surface)).foregroundStyle(Theme.text)
        }
        Button(action: onNext) {
          HStack { Text(survival ? "Next run" : "Next round"); Image(systemName: "chevron.right") }.font(.headline).frame(maxWidth: .infinity).padding(.vertical, 14)
        }
        .background(RoundedRectangle(cornerRadius: 18).fill(Color(hex: 0xf5f5f7))).foregroundStyle(Theme.background)
      }
      MoveStrip(items: strip, cursor: cursor, max: last, onSeek: seek)
      ratingCard
      RatingsList(items: moved).padding(.top, 10)
      if survival {
        SurvivalSummary(finish: finish, prefs: model.prefs, scoredInPoints: model.scoredInPoints, before: model.before ?? SurvivalRecord())
      } else {
        summary
      }
      if let blunder { compare(blunder) }
      if survival {
        VStack(spacing: 0) {
          MissedPrepList(misses: finish.ended.misses, onSeek: seek)
          MovesSurvivedList(tree: model.tree, line: run.played, record: store.state.survival, moves: finish.ended.moves)
          SurvivalEndActions(played: sansToMoveText(run.played + (blunder.map { [$0.played] } ?? [])), onChangeOptions: onChangeOptions)
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
    return lensMarks(lens, shownFen, run.color, cursor > 0 ? fens[cursor - 1] : nil)
  }

  /// The run's moves, a miss on the position it was asked in, then the blunder beside the engine's move.
  private var strip: [StripItem] {
    let label = { (ply: Int) in ply % 2 == 0 ? "\(ply / 2 + 1)." : nil }
    let mine = { (ply: Int) in (ply % 2 == 0) == (run.color == .w) }
    let missed = Set(finish.ended.misses.map(\.ply))
    var items = run.played.enumerated().map { ply, san in
      StripItem(
        san: san, label: label(ply),
        tone: ply < run.opened ? .ghost : missed.contains(ply) ? .bad : mine(ply) ? .mine : .theirs,
        current: missed.contains(ply) ? cursor == ply : cursor == ply + 1 && !missed.contains(cursor) && !onBlunder,
        seek: missed.contains(ply) ? ply : ply + 1)
    }
    if let blunder {
      items.append(StripItem(san: blunder.played, label: label(last), tone: .bad, current: onBlunder, seek: last))
      if let best = blunder.best { items.append(StripItem(san: best, label: label(last), tone: .good, seek: last)) }
    }
    return items
  }

  /// The ratings this run moved that the end screen names: favorites and the
  /// opening it was played in, not every opening above it. The run's own
  /// opening plays on its own card instead.
  private var moved: [RatingsList.Item] {
    let playedIn = deepestNodeWithin(model.tree, nodeById(model.tree, run.openingId), run.played).id
    let favorites = model.favorites
    return model.ratings.changes
      .filter { JSRound($0.delta) != 0 }
      .filter { ($0.id == playedIn || favorites.contains($0.id)) && !(moment != nil && $0.id == model.openingId && !$0.ext) }
      .map { RatingsList.Item(id: $0.id, ext: $0.ext, name: nodeById(model.tree, $0.id).name, delta: $0.delta, after: $0.after) }
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

  /// Survival's: the blunder beside the engine's move, or a miss beside your prep, where they were played.
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
      .foregroundStyle(Theme.text)
      Spacer()
      Text(openingName(model.tree, model.openingId)).font(.headline).foregroundStyle(Theme.text).lineLimit(1)
      Spacer()
      Text("\(finish.ended.extras.points)").font(.subheadline.bold().monospacedDigit()).foregroundStyle(Theme.text2)
        .padding(.horizontal, 12).padding(.vertical, 5).background(Capsule().fill(Theme.surface2))
    }
  }

  /// How it ended, what it scored, and how the prep went.
  private var summary: some View {
    let state = finish.ended
    return VStack(spacing: 6) {
      Text(endingTitle(finish.how, state.run.played.count)).font(.subheadline).foregroundStyle(isBad ? Theme.bad : Theme.text2)
      Text("\(state.extras.points) point\(state.extras.points == 1 ? "" : "s")").font(.largeTitle.bold()).foregroundStyle(Theme.text)
      Text("Survived \(state.moves) move\(state.moves == 1 ? "" : "s")").font(.subheadline).foregroundStyle(Theme.text)
      if let prep = prepSummary(model.session.answers.filter(\.correct).count, model.session.answers.count, model.session.prepTimes, model.session.bookMoves) {
        Text(prep).font(.footnote).foregroundStyle(Theme.text2)
      }
      if !state.misses.isEmpty {
        Text("\(state.misses.count) miss\(state.misses.count == 1 ? "" : "es")").font(.footnote).foregroundStyle(Theme.bad)
      }
    }
    .frame(maxWidth: .infinity).padding(.vertical, 18)
    .background(RoundedRectangle(cornerRadius: 18).fill(Theme.surface))
  }

  private var isBad: Bool {
    if case .blunder = finish.how { return true }
    if case .lost = finish.how { return true }
    return false
  }

  /// The opening's own rating, as this run moved it.
  private var moment: RatingMoment? {
    guard let r = model.ratings.byKey[model.openingId], JSRound(r.after - r.before) != 0,
      nodeById(model.tree, model.openingId).depth > 0
    else { return nil }
    return RatingMoment(name: openingName(model.tree, model.openingId), before: r.before, after: r.after)
  }

  @ViewBuilder private var ratingCard: some View {
    if let moment, played {
      RatingCardView(moment: moment, rating: moment.after, shown: moment.after, width: rankOf(moment.after).progress)
        .transition(.move(edge: .top).combined(with: .opacity))
    }
  }
}
