import ChessCore
import Engine
import Model
import SwiftUI

/// A run in play: the board, what floats over it, and the dock under it.
/// The board takes the screen's width first; the dock (goal card, status,
/// lenses) has what is left, so nothing in it can shrink the board.
/// A Survival run you set up (no Autopilot round) adds its own app bar with the clock.
struct RunView: View {
  @Bindable var model: RunModel
  let onExit: () -> Void
  /// Analysis on the run, over its end screen.
  var onAnalyze: (() -> Void)?
  @Environment(AppStore.self) var store
  @State private var lens: LensKind? = Self.pinnedLens
  @State private var planOpen = false
  /// The plan the player last saw: the Plan button pulses once the plan is another.
  @State private var planSeen: String?
  @State private var planSeeded = false
  @State private var breaks: (fen: String, found: PawnBreaks.Breaks)?

  /// A Middlegame run, not Play's round.
  var survival: Bool { model.round == nil }

  var body: some View {
    ZStack {
      board
      if model.intro == .announce {
        if survival {
          PlayIntroCover(trail: introTrail, mode: "Middlegame")
        } else {
          PlateIntroCover {
            IntroPlate(
              name: openingName(model.tree, model.introOpening), sans: nodeById(model.tree, model.introOpening).sans,
              color: model.run.color, span: model.span)
          }
        }
      }
    }
    .contentShape(Rectangle())
    .onTapGesture { if model.intro == .announce { model.toBoard() } }
  }

  private var board: some View {
    VStack(spacing: 0) {
      if survival {
        SurvivalRunBar(model: model, onExit: close)
      } else {
        header.tip(model.tip, when: model.tip == .lineIn, inset: 16, onDismiss: model.dismissTip)
      }
      // The Eval lens's bar takes the captured row's place, so the board never moves.
      // While adding moves Growth's eval bar takes the row, with the engine's word on the answers.
      CapturedRow(fen: model.shownFen, orientation: model.run.color)
        .opacity(evalHeld || adding ? 0 : 1)
        .overlay {
          if adding {
            EvalLensBar(cp: model.evals.position)
          } else if evalHeld {
            EvalLensBar(cp: model.session.evalCp, result: endgameResult)
          }
        }
        .padding(.horizontal).padding(.top, 12)
      BoardView(
        fen: model.shownFen, orientation: model.run.color,
        interactive: model.live && !model.held && model.myTurn && !model.thinking && model.pending == nil && model.flash == nil,
        lastMove: model.held ? lastMoveOf(Array(model.introPath.prefix(model.introPly))) : lastMove, highlights: highlights, arrows: arrows, glow: model.glow, pop: model.pop,
        marks: marks, allowed: model.fill == nil ? nil : model.fillChoices.map(\.san),
        onMove: model.play
      )
      .overlay { if let pulse = model.edgePulse { EdgePulse(color: pulse.found ? Theme.good : Theme.bad).id(pulse.id) } }
      .overlay(alignment: .top) { flash }
      .overlay { if model.pulse { IntroPulse() } }
      .overlay { if adding { AddingBorder() } }
      .overlay {
        if let held = model.flash {
          FlashRings(loose: held.loose, orientation: model.run.color, onTakeBack: model.takeBack)
        }
      }
      .padding(.horizontal).padding(.top, 6)
      .layoutPriority(1)
      .onTapGesture { if model.intro == .replay { model.skipIntro() } }
      dock.padding(.horizontal).frame(maxHeight: .infinity, alignment: .top)
    }
    // Any touch clears a miss or a note over the board.
    .simultaneousGesture(DragGesture(minimumDistance: 0).onChanged { _ in model.clearOverlays() })
    .task(id: adding ? "\(model.run.fen)|\(model.atHole)|\(model.listed.map(\.san))" : nil) {
      guard adding else { return }
      model.askEvals()
      model.askSoundness()
    }
    .task(id: lens == .pawns ? model.shownFen : nil) {
      guard lens == .pawns else { return }
      let fen = model.shownFen
      let found = await PawnBreaks.find(HintEngine.shared, fen)
      if !Task.isCancelled { breaks = (fen, found) }
    }
  }

  /// Debug builds can pin a lens with `PIN_LENS=pieces`, for screenshots.
  private static var pinnedLens: LensKind? {
    #if DEBUG
      ProcessInfo.processInfo.environment["PIN_LENS"].flatMap(LensKind.init(rawValue:))
    #else
      nil
    #endif
  }

  /// The Eval lens's word on an endgame, from your side: exact where the tables or a known ending settle it,
  /// otherwise from the engine's score.
  private var endgameResult: EndResult? {
    let fen = model.shownFen
    guard isEndgame(fen) || (fen == model.run.fen && model.endgameOn) else { return nil }
    let me = model.run.color
    return exactResult(fen, for: me) ?? model.session.evalCp.map { resultOf(me, $0) }
  }

  /// Moves are being added to the Playbook.
  private var adding: Bool { model.fill != nil }

  private var lensEnabled: Bool { model.live && model.intro == .done }
  private var evalHeld: Bool { lens == .eval && lensEnabled }

  /// What the held lens draws: `useLens`.
  private var marks: LensMarks? {
    guard let lens, lensEnabled else { return nil }
    let me = model.run.color
    let fens = walkSan(Array(model.run.played.dropLast())).fens
    var marks = heldLens(lens, model.shownFen, me, model.run.played.isEmpty ? nil : fens.last)
    if lens == .eval { marks.tints = evalLensTints(model.session.lastJudged, played: model.run.played.count) }
    if lens == .pawns, let breaks, breaks.fen == model.shownFen {
      let sides: [ChessCore.Color] = [.w, .b]
      marks.arrows = sides.compactMap { (side: ChessCore.Color) -> LensArrow? in
        guard let move = breaks.found[side] else { return nil }
        return LensArrow(from: move.from, to: move.to, tone: side == me ? "mine" : "theirs")
      }
    }
    return marks
  }

  private var header: some View {
    ZStack {
      VStack(spacing: 6) {
        Text(model.headerName).font(.headline).foregroundStyle(Theme.text).lineLimit(1)
        if model.endgameOn {
          // Endgame rules, on for the rest of the game once it reaches an endgame: moves are judged by the result they keep.
          Text("ENDGAME").font(.system(size: 11, weight: .bold)).tracking(0.7).foregroundStyle(Theme.text2)
        } else {
          PrepSegmentsView(span: model.span, height: 4).frame(maxWidth: 150)
        }
      }
      .padding(.horizontal, 60)
      HStack {
        Button(action: close) {
          Image(systemName: "xmark").font(.headline).frame(width: 38, height: 38).background(Circle().fill(Theme.surface))
        }
        .foregroundStyle(Theme.text).buttonStyle(.plain)
        Spacer()
      }
    }
    .padding(.horizontal).padding(.vertical, 10)
  }

  /// Under the board: the lenses, then what a held lens shows, or the goal and the status.
  private var dock: some View {
    let fens = planFens
    let plan = PlanTrails.of(fens, model.run.color).current?.plan.key
    return VStack(spacing: 0) {
      LensBar(
        held: $lens, lenses: LENSES, enabled: lensEnabled, plan: $planOpen, planEnabled: lensEnabled && plan != nil,
        planPulse: planSeeded && plan != nil && plan != planSeen, spotlight: model.tip == .lens ? .pawns : nil
      )
      .opacity(model.held ? 0 : 1).allowsHitTesting(!model.held)
      .tip(model.tip, when: model.tip == .lens && lens == nil, arrowAt: 0.1, onDismiss: model.dismissTip)
      VStack(spacing: 0) {
        if lens == .eval {
          EvalRunCard(trail: model.session.evalTrail, last: model.session.lastJudged, color: model.run.color)
        } else if let lens {
          LensLegend(kind: lens, endgame: isEndgame(model.shownFen))
        } else if planOpen {
          // A long plan card scrolls rather than run off the dock.
          ScrollView { PlanLegend(fens: fens, me: model.run.color) }.scrollIndicators(.hidden).scrollBounceBehavior(.basedOnSize)
        } else if model.intro == .plan {
          HandoffPlanCard(fens: fens, me: model.run.color)
        } else if model.blunder != nil {
          ending
        } else if model.fill != nil {
          InlineFillPanel(model: model).padding(.top, 10)
        } else {
          goalSlot.padding(.top, 12)
          status.padding(.top, 14)
            .tip(model.tip, when: model.tip == .book || model.tip == .outOfBook, arrowAt: 0.6, onDismiss: model.dismissTip)
        }
      }
      // Gives way before the board does: what doesn't fit is cut, never pushed up, and can't take a touch outside it.
      .frame(minHeight: 0, maxHeight: .infinity, alignment: .top).clipped().contentShape(Rectangle())
      footer.padding(.top, 10).padding(.bottom, 8).opacity(model.blunder == nil ? 1 : 0)
    }
    // The plan when the lenses wake is the one the player starts with; a tap on Plan sees the one up now.
    .onChange(of: lensEnabled, initial: true) {
      if lensEnabled && !planSeeded {
        planSeen = plan
        planSeeded = true
      }
    }
    .onChange(of: planOpen) { if planOpen { planSeen = plan } }
    // A run that ends closes the plan and any lens, so its ending shows.
    .onChange(of: model.live) {
      if !model.live {
        planOpen = false
        lens = nil
      }
    }
  }

  /// The game's positions up to the board as shown.
  private var planFens: [String] {
    let fens = walkSan(model.run.played).fens
    let shown = model.shownFen
    if fens.last == shown { return fens }
    if let i = fens.lastIndex(of: shown) { return Array(fens.prefix(i + 1)) }
    return fens + [shown]
  }

  /// The X: once play is under way it ends the round and goes to the end screen; before that it leaves.
  private func close() {
    if model.blunder != nil {
      model.continueToEnd()
    } else if model.live && model.intro == .done {
      model.endRound()
    } else {
      onExit()
    }
  }

  /// One fixed-height slot: the goal past prep, else the moves played for you.
  @ViewBuilder private var goalSlot: some View {
    Group {
      if model.intro == .replay, let handoff = model.handoff {
        HandoffMoves(handoff: handoff, played: model.introPly)
      } else if model.intro == .replay {
        movesLine(sansToMoveText(Array(model.introPath.prefix(model.introPly))))
      } else if !model.held && model.autoplayNote {
        movesLine("The moves up to your \(openingName(model.tree, model.introOpening)) were played for you.")
      } else if !model.held, model.prefs.missions, !model.tipsInPlay, let mission = model.session.state.extras.mission {
        GoalCard(mission: mission)
      } else if model.run.opened > 0 {
        movesLine("From \(sansToMoveText(Array(model.run.played.prefix(model.run.opened))))")
      } else {
        Color.clear
      }
    }
    .frame(height: GoalCard.height)
  }

  private func movesLine(_ text: String) -> some View {
    Text(text).font(.footnote).foregroundStyle(Theme.text2).multilineTextAlignment(.center).lineLimit(2)
      .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  /// Whose move, where you stand against your prep, and the combo, on one line.
  private var status: some View {
    HStack(spacing: 9) {
      if model.thinking || model.pending != nil {
        ProgressView().controlSize(.small)
      } else {
        Circle().fill(model.run.color == .w ? SwiftUI.Color.white : SwiftUI.Color.black).frame(width: 12, height: 12)
          .overlay(Circle().stroke(Theme.text3))
      }
      Text(model.pending != nil ? "Judging" : model.myTurn && !model.thinking ? "Your move" : "Reply")
        .font(.headline).foregroundStyle(Theme.text)
      if model.momentHere {
        Text("There's something here").font(.subheadline.bold()).foregroundStyle(Theme.accent)
      } else if model.foundIt {
        Text("Found it").font(.subheadline.bold()).foregroundStyle(Theme.good)
      } else if let label = model.label {
        let prep = prepStatusText(label)
        Text(prep.text).font(.subheadline.bold()).foregroundStyle(prep.color)
      }
      let multiplier = comboMultiplier(model.session.state.extras.combo)
      if model.prefs.combo && multiplier > 1 {
        Text("\u{00d7}\(multiplier)").font(.system(size: 12.5, weight: .heavy).monospacedDigit()).foregroundStyle(Theme.good)
          .padding(.horizontal, 9).padding(.vertical, 3).background(Capsule().fill(Theme.good.opacity(0.12)))
      }
    }
    .lineLimit(1).minimumScaleFactor(0.85)
    .frame(height: 28)
  }

  @ViewBuilder private var footer: some View {
    if model.intro == .plan {
      HandoffPlayButton(onPlay: model.playFromHandoff)
    } else {
      runFooter
    }
  }

  private var runFooter: some View {
    HStack {
      let misses = model.session.state.misses.count
      Text(misses > 0 ? "\(misses) miss\(misses == 1 ? "" : "es") so far" : "").font(.footnote).foregroundStyle(Theme.text2)
      Spacer()
      if model.holeGap != nil && model.myTurn && model.live && model.pending == nil {
        Button { model.growHere() } label: { Label("Grow here", systemImage: "plus") }
          .buttonStyle(PlayButtonStyle(kind: .soft, height: 34, radius: 17, font: 13.5))
      }
      if model.handoff != nil && model.intro == .replay {
        Button { model.skipIntro() } label: { Text("Skip").foregroundStyle(Theme.text) }
          .buttonStyle(PlayButtonStyle(kind: .soft, height: 34, radius: 17, font: 13.5))
      }
    }
  }

  /// A blunder ends the run: its name, then Analyze or on to the end screen.
  /// Analyze passes the end screen on the way, so leaving Analysis lands there.
  private var ending: some View {
    VStack(spacing: 12) {
      HStack(spacing: 8) {
        Icon(name: "cross", size: 18).frame(width: 26, height: 26).background(Circle().fill(Theme.bad.opacity(0.14)))
        Text(endingTitle(model.session.ending!, model.run.played.count)).font(.system(size: 19, weight: .heavy)).tracking(-0.19)
      }
      .foregroundStyle(Theme.bad).padding(.vertical, 6)
      HStack(spacing: 8) {
        if let onAnalyze {
          Button {
            model.continueToEnd()
            onAnalyze()
          } label: {
            Label("Analyze", systemImage: "magnifyingglass")
          }
          .buttonStyle(PlayButtonStyle(block: true))
        }
        Button { model.continueToEnd() } label: { HStack(spacing: 8) { Text("Continue"); Icon(name: "next", size: 18) } }
          .buttonStyle(PlayButtonStyle(kind: .primary, block: true))
      }
    }
    .padding(.top, 16)
  }

  @ViewBuilder private var flash: some View {
    if let caption = marks?.caption {
      Text(caption).font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.text).multilineTextAlignment(.center)
        .padding(.horizontal, 14).padding(.vertical, 6)
        .background(Capsule().fill(Theme.surface)).shadow(color: .black.opacity(0.45), radius: 10, y: 6)
        .padding(.top, 8)
    } else if model.intro == .replay {
      // While the way in plays; the opening's name is in the header already.
      Text("Autoplay").font(.system(size: 15, weight: .bold)).foregroundStyle(Theme.background)
        .padding(.horizontal, 16).padding(.vertical, 8)
        .background(Capsule().fill(Theme.accent)).shadow(color: .black.opacity(0.5), radius: 15, y: 10)
        .allowsHitTesting(false)
        // Over the gap above the board, not on the back rank's pieces.
        .offset(y: -42)
        .introPillIn().id("replay")
    } else if let miss = model.miss {
      pill("Off your prep", Theme.accent).id("miss-\(miss.from)\(miss.to)")
    } else if let note = model.note {
      pill(note.text, note.tone == "good" ? Theme.good : note.tone == "bad" ? Theme.bad : Theme.accent).id("note-\(note.text)")
    }
  }

  /// A verdict over the top of the board: `.board-flash.top` with its `.flash-pill`, fading in, held and out.
  private func pill(_ text: String, _ color: SwiftUI.Color) -> some View {
    Text(text).font(.system(size: 19, weight: .heavy)).foregroundStyle(color).multilineTextAlignment(.center)
      .padding(.leading, 14).padding(.trailing, 22).padding(.vertical, 12)
      .background(Capsule().fill(Theme.surface)).shadow(color: .black.opacity(0.5), radius: 15, y: 10)
      .padding(.top, 10).padding(.horizontal, 20)
      .boardFlash()
  }


  private var lastMove: (from: String, to: String)? {
    if model.blunder != nil { return nil }
    // The green on the move just added takes the last move's tint, as in Growth.
    if adding && model.justAdded != nil { return nil }
    if let held = model.flash { return (held.move.from, held.move.to) }
    if let pending = model.pending { return (pending.from, pending.to) }
    return lastMoveOf(model.run.played)
  }

  private var highlights: [String: SwiftUI.Color] {
    if adding, let added = model.justAdded { return [added.from: Theme.good, added.to: Theme.good] }
    if let b = model.blunder { return [b.move.from: Theme.bad, b.move.to: Theme.bad] }
    if let best = model.missedBest { return [best.from: Theme.bad, best.to: Theme.bad] }
    return [:]
  }

  private var arrows: [BoardArrow] {
    if let b = model.blunder {
      return b.threat.map { [BoardArrow(from: $0.from, to: $0.to, color: Theme.bad)] } ?? []
    }
    if let miss = model.miss { return [BoardArrow(from: miss.from, to: miss.to, color: Theme.good)] }
    if model.atHole && !model.thinking { return holeArrows(model) }
    return []
  }
}

/// The board's steady accent edge while moves are being added.
private struct AddingBorder: View {
  var body: some View {
    GeometryReader { geo in
      // Just outside the board, clear of the coordinates on its edge squares.
      RoundedRectangle(cornerRadius: geo.size.width * 0.03 + 4)
        .strokeBorder(Theme.accent, lineWidth: 3)
        .padding(-4)
        .shadow(color: Theme.accent.opacity(0.6), radius: 10)
    }
    .allowsHitTesting(false)
  }
}

/// `Math.round`.
func JSRound(_ x: Double) -> Double {
  let down = x.rounded(.down)
  return x - down >= 0.5 ? down + 1 : down
}
