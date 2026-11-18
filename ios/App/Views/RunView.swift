import ChessCore
import Engine
import Game
import Model
import SwiftUI

/// A run in play: the board, what floats over it, and the dock under it.
/// The board takes the screen's width first; the dock (goal card, status,
/// lenses) has what is left, so nothing in it can shrink the board.
/// A run you set up (no Play round) adds its own app bar with the clock.
struct RunView: View {
  @Bindable var model: RunModel
  let onExit: () -> Void
  /// Analysis on the run, over its end screen.
  var onAnalyze: (() -> Void)?
  /// Next run: Play's next round, without the end screen.
  var onNextRun: (() -> Void)?
  /// Play's next round, drawn from the deck under a finished run: its card, taken once. Nil keeps the end screen.
  var onDraw: (() -> RoundCard?)?
  /// The drawn card has grown onto the board: the next round takes over.
  var onDealt: (() -> Void)?
  @Environment(AppStore.self) var store
  @State private var lens: LensKind? = Self.pinnedLens
  @State private var planOpen = false
  /// The plan the player last saw: the Plan button pulses once the plan is another.
  @State private var planSeen: String?
  @State private var planSeeded = false
  @State private var breaks: (fen: String, found: PawnBreaks.Breaks)?
  /// The X mid-round asks before it ends the session.
  @State private var askingToEnd = false
  /// The finished run, analysed on its board while the deck is under it.
  @State private var analysis: RunAnalysis?
  /// A step through it part of the way along, as the deck's swipe has it.
  @State private var slid: BoardSlide?
  @Environment(\.scenePhase) private var scenePhase

  /// A Middlegame run, not Play's round.
  var standalone: Bool { model.round == nil }

  /// The run is over and stays on the board, with the deck to draw the next one from.
  var drawing: Bool { onDraw != nil && model.finish != nil && !model.advancing }

  /// The tip over the deck, the first time a Play round ends on it.
  private static let deckTip = "Tap the deck to deal your next game."
  /// The deck's tip is up: no tip on the game, and the deck under a finished run for the first time.
  private var deckTipUp: Bool { drawing && model.tip == nil && !store.state.settings.seenDeckTip }

  /// The game as played, the move that ended it last.
  private var gameLine: [String] {
    if case .blunder(let played, _, _, _, _) = model.session.ending { return model.run.played + [played] }
    return model.run.played
  }

  /// The board's position: the analysed one while the deck is under a finished run.
  private var boardFen: String { drawing ? analysis?.fen ?? model.shownFen : model.shownFen }

  /// On the game's own last position, where it ended.
  private var atGameEnd: Bool { !drawing || analysis?.atEnd ?? true }

  private var deckSteps: DeckSteps {
    DeckSteps(
      can: { analysis?.canStep($0) ?? false },
      slide: { dir, progress in
        guard progress > 0, let a = analysis, let move = a.stepMove(dir) else {
          slid = nil
          return
        }
        slid = BoardSlide(move: move, before: dir < 0 ? a.fens[a.ply - 1] : a.fen, back: dir < 0, progress: progress)
      },
      step: { dir in
        withAnimation(.easeOut(duration: 0.12)) {
          slid = nil
          analysis?.step(dir)
        }
      },
      cancel: { withAnimation(.easeOut(duration: 0.16)) { slid?.progress = 0 } })
  }

  var body: some View {
    ZStack {
      board
      if model.intro == .announce {
        if standalone {
          PlayIntroCover(trail: introTrail, mode: "Middlegame")
        }
      }
    }
    // Play's round is dealt as a card on its start position, which grows into the board.
    .overlayPreferenceValue(BoardFrameKey.self) { anchor in
      if model.intro == .announce && !standalone {
        GeometryReader { geo in
          RoundDeal(card: model.card, board: anchor.map { geo[$0] }, onDone: { model.toBoard() })
        }
        .transition(.identity)
      } else if drawing {
        GeometryReader { geo in
          RoundDeal(
            board: anchor.map { geo[$0] }, draw: onDraw, onDone: onDealt, steps: deckSteps,
            // Waits for any tip on the game, such as the blunder's.
            tip: deckTipUp ? Self.deckTip : nil,
            onTip: { store.update { $0.settings.seenDeckTip = true } })
        }
        .transition(.identity)
      }
    }
    .pawnFlights(orientation: model.run.color)
    .contentShape(Rectangle())
    .onTapGesture { if model.intro == .announce { model.toBoard() } }
    .confirmationDialog("End session?", isPresented: $askingToEnd, titleVisibility: .visible) {
      Button("End session", role: .destructive) { end() }
      Button("Keep playing", role: .cancel) {}
    }
    .onChange(of: drawing, initial: true) {
      if drawing && analysis == nil { analysis = RunAnalysis(game: gameLine, engine: HintEngine.shared) }
    }
    .task(id: drawing ? analysis?.fen : nil) { await analysis?.findTop() }
    // Your move's time stops while the app is in the background or the screen is locked.
    .onChange(of: scenePhase) {
      if scenePhase == .active { model.appReturned() } else { model.appLeft() }
    }
  }

  private var board: some View {
    VStack(spacing: 0) {
      if standalone {
        VStack(spacing: 0) {
          RunHeaderBar(model: model, onExit: close)
          headerStatus.opacity(model.session.ending != nil ? 0 : 1).padding(.bottom, 4)
        }
      } else {
        header
          .clearsLens($lens)
          // One tip modifier per view: a second one's layering would lose to the first's.
          .tip(model.tip, when: Self.headerTips.contains(model.tip), arrowAt: headerArrowAt, inset: 16, onDismiss: model.dismissTip)
      }
      // The Eval lens's bar takes the captured row's place, so the board never moves.
      // While adding moves Growth's eval bar takes the row, with the engine's word on the answers.
      CapturedRow(fen: boardFen, orientation: model.run.color)
        .opacity(evalHeld || adding || drawing ? 0 : 1)
        .overlay {
          if drawing, let analysis {
            // Analysing a finished run: the Analysis screen's eval row.
            EvalRow(best: analysis.best, depth: analysis.depth)
          } else if adding {
            EvalLensBar(cp: model.evals.position)
          } else if evalHeld {
            EvalLensBar(cp: model.session.evalCp, result: endgameResult)
          }
        }
        .padding(.horizontal).padding(.top, 12)
      BoardView(
        fen: boardFen, orientation: model.run.color,
        interactive: drawing ? analysis != nil : model.live && !model.held && model.myTurn && !model.thinking && model.pending == nil && model.flash == nil,
        lastMove: model.held ? lastMoveOf(Array(model.introPath.prefix(model.introPly))) : lastMove, highlights: highlights, arrows: arrows, pop: model.pop, popId: model.popCount,
        marks: marks, bothSides: drawing, allowed: drawing || model.fill == nil ? nil : model.fillChoices.map(\.san),
        slide: drawing ? slid : nil,
        onMove: { move in
          if drawing { analysis?.play(move) } else { model.play(move) }
        }
      )
      // Under Play's deal the card stands in for the board until it has grown onto it.
      .opacity(model.intro == .announce && !standalone ? 0 : 1)
      .anchorPreference(key: BoardFrameKey.self, value: .bounds) { $0 }
      .pawnSpot("board")
      .clearsLens($lens)
      .overlay { if let pulse = model.edgePulse { EdgePulse(color: pulse.found ? Theme.good : Theme.bad).id(pulse.id) } }
      .overlay(alignment: .top) { flash }
      .overlay { if model.pulse { IntroPulse() } }
      .overlay { if let rim { BoardRim(color: rim.color) } }
      .overlay {
        if let held = model.flash {
          FlashRings(loose: held.loose, orientation: model.run.color, onTakeBack: model.takeBack)
        }
      }
      .padding(.horizontal).padding(.top, 6)
      .tip(model.tip, when: Self.boardTips.contains(model.tip), inset: 16, onDismiss: model.dismissTip)
      .layoutPriority(1)
      .onTapGesture { if model.intro == .replay { model.skipIntro() } }
      dock.padding(.horizontal).frame(maxHeight: .infinity, alignment: .top)
    }
    // Any touch clears a miss over the board.
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

  /// The tips hung from the board.
  private static let boardTips: Set<GameTip?> = [.flashCards, .prepDone, .missedMove, .freeformGame]

  /// The tips hung from the header: at the prep bar, the pawn counter, or the close button.
  private static let headerTips: Set<GameTip?> = [.prepBar, .pawns, .endSession]

  private var headerArrowAt: CGFloat { model.tip == .pawns ? 0.92 : model.tip == .endSession ? 0.08 : 0.5 }

  /// The board's rim and what the status line calls it: a replay, adding moves, a moment to find, your prep.
  private var rim: (color: SwiftUI.Color, label: String)? {
    if model.intro == .replay { return (Theme.accent, "Replay") }
    if adding { return (Theme.accent, "Adding new moves") }
    if model.blunder != nil { return nil }
    if model.momentHere { return (Theme.warn, "There\u{2019}s something here") }
    if model.inPrep { return (Theme.good, "Your prep") }
    return nil
  }

  /// The lenses are away: moves are being played for you or added, or there is a moment to find without them.
  private var lensesAway: Bool { model.intro == .replay || adding || (model.blunder == nil && model.momentHere) }

  /// A tip hangs above the dock's top: the blunder's over its name, the mission's over the goal, growth's over Done.
  private var tipAbove: Bool { model.blunder != nil || model.tip == .blunder || model.tip == .mission || model.tip == .growth }

  /// A callout is up in the lenses' place.
  private var called: Bool { model.shownCallout != nil }

  /// Prep complete, Off prep or Found it, in the lenses' place for a moment.
  @ViewBuilder private var calloutLayer: some View {
    if let callout = model.shownCallout {
      Group { if callout.missed { CalloutStrip.missed(callout.text) } else { CalloutStrip(text: callout.text, good: callout.good) } }
        .pawnSpot("callout")
        .padding(.top, 8)
        .transition(.opacity.combined(with: .offset(y: -6)))
        .id(callout.id)
    }
  }

  /// Next run: the round ends where it stands, and the next round follows.
  private func nextRun() {
    model.advancing = true
    model.endRound()
    onNextRun?()
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
    var marks = heldLens(lens, model.shownFen, me, model.run.played.isEmpty ? nil : fens.last, parts: store.state.lensParts)
    if lens == .eval, store.state.owns(.lensEvalHistory) { marks.tints = evalLensTints(model.session.lastJudged, played: model.run.played.count) }
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
        VStack(spacing: 1) {
          if let family = model.headerFamily {
            Text(family).font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.text2).lineLimit(1)
          }
          Text(model.headerName).font(.headline).foregroundStyle(Theme.text).lineLimit(1)
        }
        if model.endgameOn {
          // Endgame rules, on for the rest of the game once it reaches an endgame: moves are judged by the result they keep.
          Text("ENDGAME").font(.system(size: 11, weight: .bold)).tracking(0.7).foregroundStyle(Theme.text2)
        } else if let marker = model.marker {
          MarkerBar(moves: marker.moves, height: 4).frame(maxWidth: 150)
        } else {
          HStack(spacing: 6) {
            PrepSegmentsView(span: model.span, height: 4).frame(maxWidth: 150).pawnSpot("prep")
            if !model.session.middlegame {
              PrepPot(pot: model.pot, held: model.heldPrepPawn != nil, drain: model.potDrain)
            }
          }
        }
        // Kept in place while analysing a finished run, so the board doesn't move, but not shown.
        // Nor once the game is over, when no one has a move.
        headerStatus.opacity(drawing || model.session.ending != nil ? 0 : 1)
      }
      .padding(.horizontal, 60)
      HStack {
        Button(action: close) {
          Image(systemName: "xmark").font(.headline).frame(width: 38, height: 38).background(Circle().fill(Theme.surface))
        }
        .foregroundStyle(Theme.text).buttonStyle(.plain)
        .accessibilityLabel("Close")
        Spacer()
        PawnCounter()
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
        planPulse: planSeeded && plan != nil && plan != planSeen,
        spotlight: model.tip == .lens ? LENSES.map(\.kind).first { store.state.owns(lens: $0) } : nil, gated: true
      )
      .opacity(model.held || lensesAway || called || drawing ? 0 : 1).allowsHitTesting(!(model.held || lensesAway || called || drawing))
      // A finished run being analysed shows its moves in the lenses' place.
      .overlay {
        if drawing, let analysis { analysisStrip(analysis).opacity(called ? 0 : 1) }
      }
      .overlay(alignment: .top) { calloutLayer.animation(.easeOut(duration: 0.25), value: model.shownCallout?.id) }
      // The callout runs past the lenses' row, over the panel under it (Undo and Done while adding moves).
      .tip(model.tip, when: model.tip == .lens, arrowAt: 0.1, rest: 1, onDismiss: model.dismissTip)
      // Over a finished game, at its moves.
      .tip(model.tip, when: model.tip == .analysis && drawing, rest: 1, onDismiss: model.dismissTip)
      VStack(spacing: 0) {
        if lens == .eval {
          if store.state.owns(.lensEvalHistory) { EvalRunCard(trail: model.session.evalTrail, last: model.session.lastJudged, color: model.run.color) }
        } else if let lens {
          LensLegend(kind: lens, endgame: isEndgame(model.shownFen), safety: marks?.safety, parts: store.state.lensParts)
        } else if planOpen {
          // A long plan card scrolls rather than run off the dock.
          ScrollView { PlanLegend(fens: fens, me: model.run.color) }.scrollIndicators(.hidden).scrollBounceBehavior(.basedOnSize)
        } else if model.intro == .plan {
          HandoffPlanCard(fens: fens, me: model.run.color)
        } else if model.blunder != nil || drawing {
          ending
        } else if model.fill != nil {
          InlineFillPanel(model: model).padding(.top, 10)
        } else {
          goalSlot.padding(.top, 12)
        }
      }
      .clearsLens($lens)
      // Gives way before the board does: what doesn't fit is cut, never pushed up, and can't take a touch outside it.
      // A blunder's tip hangs above its name, over the lenses, so nothing is cut then.
      .frame(minHeight: 0, maxHeight: .infinity, alignment: .top)
      .clipShape(Rectangle().inset(by: tipAbove ? -200 : 0)).contentShape(Rectangle())
      // Over the lenses' row while a blunder's tip hangs above its name, or the mission tip above the goal.
      .zIndex(tipAbove ? 2 : 0)
      footer.padding(.top, 10).padding(.bottom, 8).opacity(model.blunder == nil && !drawing ? 1 : 0)
    }
    // The plan when the lenses wake is the one the player starts with; a tap on Plan sees the one up now.
    .onChange(of: lensEnabled, initial: true) {
      if lensEnabled && !planSeeded {
        planSeen = plan
        planSeeded = true
      }
    }
    .onChange(of: planOpen) { if planOpen { planSeen = plan } }
    // Lenses that go away take any held lens with them.
    .onChange(of: lensesAway) {
      if lensesAway {
        lens = nil
        planOpen = false
      }
    }
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

  /// The X: once play is under way it asks, then ends the round and goes Home; before that it leaves.
  /// A run over on the board, with the deck under it, leaves.
  private func close() {
    if drawing {
      onExit()
    } else if model.blunder != nil {
      model.continueToEnd()
    } else if model.live && model.intro == .done {
      // A round already called over, or one with nothing played yet, ends without asking.
      if model.run.played.count <= model.run.opened { end() } else { askingToEnd = true }
    } else {
      onExit()
    }
  }

  /// The round ends where it stands, and Home.
  private func end() {
    model.endRound()
    onExit()
  }

  /// One fixed-height slot: the moves played for you while they replay, else the goal.
  @ViewBuilder private var goalSlot: some View {
    Group {
      if model.intro == .replay, let handoff = model.handoff {
        HandoffMoves(handoff: handoff, played: model.introPly)
      } else if model.intro == .replay {
        movesLine(sansToMoveText(Array(model.introPath.prefix(model.introPly))))
      } else if !model.held, model.prefs.missions, let mission = model.session.state.extras.mission {
        GoalCard(mission: mission).pawnSpot("goal")
          .tip(model.tip, when: model.tip == .mission, arrow: .down, inset: 16, onDismiss: model.dismissTip)
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

  @ViewBuilder private var footer: some View {
    if model.intro == .plan {
      HandoffPlayButton(onPlay: model.playFromHandoff)
    } else {
      runFooter
    }
  }

  private var runFooter: some View {
    ZStack {
      runButtons
      if model.canReplay {
        Button { model.replayMoves() } label: { Label("Replay moves", systemImage: "play.fill") }
          .buttonStyle(PlayButtonStyle(kind: .soft, height: 44, radius: 12, font: 15))
          .transition(.opacity)
      }
    }
    .animation(.easeOut(duration: 0.2), value: model.canReplay)
  }

  private var runButtons: some View {
    HStack {
      Spacer()
      if model.holeGap != nil && model.myTurn && model.live && model.pending == nil {
        Button { model.growHere() } label: { Label("Grow here", systemImage: "plus") }
          .buttonStyle(PlayButtonStyle(kind: .soft, height: 44, radius: 12, font: 15))
      }
      if model.handoff != nil && model.intro == .replay {
        Button { model.skipIntro() } label: { Text("Skip").foregroundStyle(Theme.text) }
          .buttonStyle(PlayButtonStyle(kind: .soft, height: 44, radius: 12, font: 15))
      }
      if model.nextRunShown && onNextRun != nil {
        Button(action: nextRun) { HStack(spacing: 8) { Text("Next run"); Icon(name: "next", size: 16) } }
          .buttonStyle(PlayButtonStyle(kind: .soft, height: 44, radius: 12, font: 15))
          .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.accent, lineWidth: 1.5) }
      }
    }
    // Over the row, its arrow at Next run on the right.
    .tip(model.tip, when: model.tip == .nextRun, arrow: .down, arrowAt: 0.88, inset: 16, onDismiss: model.dismissTip)
  }

  /// The analysed line's moves, as on the Analysis screen: a tap or an arrow goes to a move.
  private func analysisStrip(_ analysis: RunAnalysis) -> some View {
    let items = analysis.line.enumerated().map { i, san in
      StripItem(
        san: san, label: i % 2 == 0 ? "\(i / 2 + 1)." : nil, tone: i >= analysis.ply ? .ghost : nil,
        current: i == analysis.ply - 1, seek: i + 1)
    }
    return MoveStrip(items: items, cursor: analysis.ply, max: analysis.line.count) { analysis.seek($0) }.padding(.horizontal, 16)
  }

  /// Under the prep bar: the rim's name in its color while the board has one, else whose move.
  private var headerStatus: some View {
    let turn = model.pending != nil ? "Judging" : model.myTurn && !model.thinking ? "Your move" : "Reply"
    let named = rim
    return StatusLine(
      white: model.run.color == .w,
      // A finished game says so, whatever was last on the board.
      text: drawing ? "Game over" : named?.label ?? turn,
      busy: model.thinking || model.pending != nil,
      tone: named?.color ?? Theme.text2)
  }

  /// A blunder ends the run: its name under the board for a beat, the threat drawn on it,
  /// then the end screen, which has Analyze. The blunder tip holds it until it is put away.
  /// With the deck, the run stays here as analysis: its ending's name at the game's end, else the move and who is to play.
  @ViewBuilder private var ending: some View {
    if drawing {
      Group {
        if !atGameEnd {
          analysisStatus
        } else {
          endingName.fixedSize().tip(model.tip, when: model.tip == .blunder, arrow: .down, inset: 16, onDismiss: model.dismissTip)
        }
      }
      .padding(.top, 16)
      .frame(maxWidth: .infinity)
    } else if model.canContinue {
      // Continue can take the blunder back: the board holds it until the player chooses.
      VStack(spacing: 14) {
        endingName
          .tip(model.tip, when: model.tip == .blunder, arrow: .down, inset: 16, onDismiss: model.dismissTip)
        HStack(spacing: 10) {
          Button { model.continueToEnd() } label: { Text("End run").lineLimit(1) }
            .buttonStyle(PlayButtonStyle(kind: .plain, height: 44, block: true, inset: 12))
          Button { model.buyContinue() } label: {
            HStack(spacing: 8) {
              Text("Continue")
              PawnAmount(count: CONTINUE_PRICE, size: 15, color: Theme.buttonInk)
            }
            .lineLimit(1).fixedSize()
          }
          .buttonStyle(PlayButtonStyle(kind: .accent, height: 44, block: true, inset: 12))
        }
      }
      .frame(maxWidth: .infinity)
      .padding(.top, 16)
    } else {
      endingName
        .tip(model.tip, when: model.tip == .blunder, arrow: .down, inset: 16, onDismiss: model.dismissTip)
        .frame(maxWidth: .infinity)
        .padding(.top, 16)
        .contentShape(Rectangle())
        .onTapGesture { model.continueToEnd() }
        .task(id: model.tip == .blunder) {
          guard model.tip != .blunder else { return }
          try? await Task.sleep(for: .seconds(2))
          if !Task.isCancelled { model.continueToEnd() }
        }
    }
  }

  /// Away from the game's end: the move and who is to play, or how the position stands when nothing can be played.
  @ViewBuilder private var analysisStatus: some View {
    if let analysis {
      let fen = analysis.fen
      let turn = fenTurn(fen)
      Group {
        if legalMoves(fen).isEmpty {
          Text(analysis.last?.san.hasSuffix("#") == true ? "Checkmate" : "Stalemate")
        } else {
          HStack(spacing: 8) {
            SideSquare(color: turn, size: 12)
            Text("Move \(analysis.ply / 2 + 1), \(turn == .w ? "White" : "Black") to play")
          }
        }
      }
      .font(.system(size: 16, weight: .bold)).foregroundStyle(Theme.text2).padding(.vertical, 8)
    }
  }

  /// How the run ended, in the color of the result: a loss red with its cross, a win green.
  private var endingName: some View {
    let how = model.session.ending ?? .ended
    let lostIt: Bool
    switch how {
    case .blunder, .lost: lostIt = true
    default: lostIt = false
    }
    let tone: SwiftUI.Color = lostIt ? Theme.bad : how == .won ? Theme.good : Theme.text2
    return HStack(spacing: 8) {
      if lostIt {
        Icon(name: "cross", size: 18).frame(width: 26, height: 26).background(Circle().fill(Theme.bad.opacity(0.14)))
      }
      // Ended by hand, the game is just over.
      Text(how == .ended ? "Game over" : endingTitle(how, model.run.played.count)).font(.system(size: 19, weight: .heavy)).tracking(-0.19)
    }
    .foregroundStyle(tone).padding(.vertical, 6)
  }

  @ViewBuilder private var flash: some View {
    if let caption = marks?.caption {
      Text(caption).font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.text).multilineTextAlignment(.center)
        .padding(.horizontal, 14).padding(.vertical, 6)
        .background(Capsule().fill(Theme.surface)).shadow(color: .black.opacity(0.45), radius: 10, y: 6)
        .padding(.top, 8)
    }
  }

  private var lastMove: (from: String, to: String)? {
    if drawing && !atGameEnd { return analysis?.last.map { ($0.from, $0.to) } }
    if model.blunder != nil { return nil }
    // The green on the move just added takes the last move's tint, as in Growth.
    if adding && model.justAdded != nil { return nil }
    if let held = model.flash { return (held.move.from, held.move.to) }
    if let pending = model.pending { return (pending.from, pending.to) }
    return lastMoveOf(model.run.played)
  }

  private var highlights: [String: SwiftUI.Color] {
    if !atGameEnd { return [:] }
    if adding, let added = model.justAdded { return [added.from: Theme.good, added.to: Theme.good] }
    if let b = model.blunder { return [b.move.from: Theme.bad, b.move.to: Theme.bad] }
    return [:]
  }

  private var arrows: [BoardArrow] {
    // Analysing: the top move, once the engine has it; none while a step is part of the way along.
    if drawing && !(atGameEnd && model.blunder != nil) {
      guard slid == nil || slid?.progress == 0, let top = analysis?.top else { return [] }
      return [BoardArrow(from: top.from, to: top.to, color: Theme.book, over: true)]
    }
    if let b = model.blunder {
      return b.threat.map { [BoardArrow(from: $0.from, to: $0.to, color: Theme.bad, over: true)] } ?? []
    }
    if let miss = model.miss { return [BoardArrow(from: miss.from, to: miss.to, color: Theme.good)] }
    // The blunder Continue took back: what it would have allowed, until your next move.
    if let threat = model.takenBack?.threat { return [BoardArrow(from: threat.from, to: threat.to, color: Theme.bad, over: true)] }
    // A chance you missed: its move, until your next one.
    if let best = model.missedBest { return [BoardArrow(from: best.from, to: best.to, color: Theme.missed, over: true)] }
    if model.atHole && !model.thinking {
      return holeArrows(model)
    }
    return []
  }
}
