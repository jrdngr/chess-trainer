import Book
import ChessCore
import Engine
import Foundation
import Model
import Observation

/// One Survival run on screen, Autopilot's or one you set up. It feeds the controller what happens (your moves, the judge's verdicts,
/// the opponent's replies), carries out the effects in order, and keeps what
/// the view draws.
@MainActor @Observable
final class RunModel {
  enum Phase { case playing, blunder, over }
  /// The round's intro: announced full screen, then the way in played out on a locked board.
  /// A Middlegame run then shows the plan card at the handoff before your clock starts.
  enum Intro { case announce, replay, plan, done }

  /// How long the announcement holds, and the beat between replayed moves (a Middlegame run's is quicker).
  static let announceMs = 2.5, replayMs = 0.4, handoffReplayMs = 0.12, pulseMs = 0.9

  /// How long a miss, a score popup and a note stay over the board (a touch clears a miss or a note sooner); the opponent's beat.
  static let missMs = 2.0, scoreMs = 1.4, noteMs = 2.0, replyMs = 0.42
  /// How long the board's edge pulses when a moment is settled.
  static let edgePulseMs = 1.5
  /// How long the Undefended flash holds your move before it lands.
  static let flashMs = 1.3

  /// Autopilot's round; nil for a run set up on Survival's or Middlegame's own screen.
  let round: AutoRound?
  /// A Middlegame run's handoff: the moves played for you, and who chose each.
  let handoff: Handoff?
  let selection: Selection
  let tree: OpeningTree
  let index: ReferenceIndex
  private let store: AppStore
  /// Your favorite openings, for the end screen's ratings list.
  var favorites: [String] { store.state.settings.favoriteOpenings }
  private let engine: ChessEngine
  private let ctx: RunContext

  private(set) var session: RunSession
  private(set) var phase = Phase.playing
  private(set) var pop: Pop?
  private(set) var note: Note?
  private(set) var miss: MissFlash?
  /// The moment's move you missed: its squares stay red until your next move.
  private(set) var missedBest: (from: String, to: String)?
  /// The board's edge pulsing for a moment settled: green found, red missed. `id` restarts it.
  private(set) var edgePulse: (found: Bool, id: Int)?
  /// The moment just settled was found: the status line says so until your next move.
  private(set) var foundIt = false
  /// Your move, on the board while the engine judges it.
  private(set) var pending: LegalMove?
  private(set) var thinking = false
  private(set) var baseline: Baseline?
  /// Each opening's rating this run: where it stood before, and where it is now.
  private(set) var ratings = OrderedRatings()
  private(set) var finish: Finish?
  /// The end screen has opened once: its verdict and rating change have played, and stay at rest after.
  var endSeen = false
  /// Moves being added to the Playbook mid-run, at the gap the run reached.
  struct Fill {
    var gap: Gap
    var size: Int
    /// Each move added: the run before it, and the line whose node Undo removes.
    var steps: [(session: RunSession, remove: [String])] = []
    var added: Int { steps.count }
  }
  private(set) var fill: Fill?
  /// The move just added while adding moves, green on the board until their reply.
  private(set) var justAdded: (from: String, to: String)?
  @ObservationIgnored let tonedMemo = Memo<[NudgedMove]>()
  /// The gap the run reached when the engine said no new move: the player can
  /// still add one while it is their move there.
  private(set) var holeGap: Gap?
  /// The run has reached its one hole and asked about it.
  private var holeAsked = false
  /// A new player's first game: nothing saved, adding moves from move one, with tips.
  private(set) var firstGame = false
  /// A first game picked from the welcome's tutorial, not reached after Skip.
  private(set) var tutorial = false
  /// The first game's tip on screen.
  private(set) var tip: FirstGameTip?
  /// The side's Playbook that moves were added to this run.
  private var filledRep: String?
  private(set) var intro = Intro.announce
  /// How many of the way in's moves the replay has played.
  private(set) var introPly = 0
  private var spanHeld: PrepSpan?
  /// A move held back by the Undefended flash: what it leaves loose.
  private(set) var flash: (move: LegalMove, loose: [String])?
  /// Counts held moves, so a flash's timer lands only the hold it began with.
  private var flashCount = 0
  /// The Survival record as it stood before this run ended, to tell a new best.
  private(set) var before: SurvivalRecord?

  private var picker: () -> Double
  /// When your turn began: the clock counts from here.
  private(set) var turnStarted = Date()
  private var tasks: [Task<Void, Never>] = []
  /// What a clean end of prep grows with.
  private let growth: GrowthPrefs

  /// Autopilot's round, on Autopilot's own options.
  convenience init?(round: AutoRound, selection: Selection, store: AppStore, tree: OpeningTree, index: ReferenceIndex, engine: ChessEngine) {
    let seed = (Env.random() * 2_147_483_648).rounded(.down)
    guard let begun = startSurvival(survivalOptions(round, store.state, tree, selection, seed: seed)) else { return nil }
    self.init(
      begun: begun, round: round, prefs: autoSurvival(store.state.settings.autopilot), growth: AUTO_GROWTH,
      selection: selection, store: store, tree: tree, index: index, engine: engine)
    store.update { $0.noteStart(startKind(start: round.pick.start, at: round.at)) }
  }

  /// A new player's first game: White, nothing saved, adding moves from move one.
  convenience init?(firstGame store: AppStore, tree: OpeningTree, index: ReferenceIndex, engine: ChessEngine) {
    var repId = ""
    store.update { repId = $0.ensureRepertoire(.w) }
    guard let rep = store.state.repertoires[repId] else { return nil }
    self.init(
      round: firstGameRound(tree), selection: Selection(color: .w, opening: ANY_OPENING), store: store, tree: tree, index: index,
      engine: engine)
    firstGame = true
    tutorial = !store.state.settings.tips.isEmpty
    holeAsked = true
    fill = Fill(gap: firstMoveGap(rep, index), size: store.state.settings.movesPerFill)
  }

  /// A run set up on Survival's screen, on those options: `start` with no plan.
  convenience init?(survival options: StartOptions, prefs: SurvivalPrefs, growth: GrowthPrefs, selection: Selection,
                    store: AppStore, tree: OpeningTree, index: ReferenceIndex, engine: ChessEngine) {
    guard let begun = startSurvival(options) else { return nil }
    self.init(begun: begun, round: nil, prefs: prefs, growth: growth, selection: selection, store: store, tree: tree, index: index, engine: engine)
  }

  /// A Middlegame run, begun at its handoff: `options` start at `handoff.line`.
  convenience init?(middlegame options: StartOptions, handoff: Handoff, prefs: SurvivalPrefs, selection: Selection,
                    store: AppStore, tree: OpeningTree, index: ReferenceIndex, engine: ChessEngine) {
    var options = options
    options.at = handoff.line
    guard let begun = startSurvival(options), begun.state.run.played == handoff.line else { return nil }
    self.init(
      begun: begun, round: nil, handoff: handoff, prefs: middlegamePrefs(prefs), growth: store.state.settings.growth,
      selection: selection, store: store, tree: tree, index: index, engine: engine)
  }

  private init(begun: SurvivalStart, round: AutoRound?, handoff: Handoff? = nil, prefs: SurvivalPrefs, growth: GrowthPrefs, selection: Selection,
               store: AppStore, tree: OpeningTree, index: ReferenceIndex, engine: ChessEngine) {
    self.round = round
    self.handoff = handoff
    self.selection = selection
    self.store = store
    self.tree = tree
    self.index = index
    self.engine = engine
    self.growth = growth
    picker = mulberry32(seed: (Env.random() * 2_147_483_648).rounded(.down))
    session = handoff != nil ? beginMiddlegame(begun) : beginSession(begun)
    let losses = lossesIn(store.state.repertoireList)
    ctx = RunContext(
      index: index, prefs: prefs, autopilot: round != nil,
      kindOf: { line, san in playedKinds(index, line + [san], line.count % 2 == 0 ? .w : .b, losses).last ?? .book },
      lossOf: { losses[$0] })
  }

  var prefs: SurvivalPrefs { ctx.prefs }
  /// Who plays the other side past the book. Autopilot's opponent always plays at your strength.
  var opponentLevel: Level {
    round != nil ? levelMatching(store.state.strength) : prefs.opponentLevel(store.state.strength)
  }
  /// With moments, missions or the combo on, a run is scored in points as well as moves.
  var scoredInPoints: Bool { prefs.moments || prefs.missions || prefs.combo }
  /// Announcing or replaying: the board is locked, and the opponent waits.
  var held: Bool { intro != .done }
  /// The moves the intro plays out: the way in, with Autoplay on; a Middlegame run's handoff always.
  var introPath: [String] { handoff != nil || store.state.settings.autoplay ? Array(run.played.prefix(run.opened)) : [] }
  /// The opening the round is announced as. A run from move one is named by the opening it is steered toward.
  var introOpening: String {
    run.enteredIn ?? round?.pick.opening.id
      ?? deepestNodeWithin(tree, nodeById(tree, run.openingId), Array(run.played.prefix(run.opened))).id
  }

  /// How far into your prep the run stands, out of how far it goes along this line. Held once off prep.
  /// None for an Autopilot run on My Playbook, which always starts from move one.
  var span: PrepSpan? {
    if round != nil && selection.opening == ANY_OPENING && !firstGame { return nil }
    if session.prepStatus == .off { return spanHeld }
    let line = run.played + continuation(session.source, run)
    // Moves added this run are prep too, though the run's source was read before them.
    let added = filledRep.map { prepIndex(store.state.repertoires[$0]) } ?? [:]
    let prepAt = filledRep != nil ? { (fen: String) in added[positionKey(fen)] ?? [] } : session.source.prepAt
    let total = prepDepth(line, run.color, prepAt, run.opened)
    let book = session.prepStatus == .complete && session.bookTo != nil ? max(0, session.bookTo! - total) : 0
    let losses = lossesIn(store.state.repertoireList)
    let ext = bookLength(playedKinds(index, Array(line.prefix(total)), run.color, losses))
    return PrepSpan(played: min(run.played.count, total), total: total, book: book > 0 ? book : nil, ext: ext < total ? ext : nil)
  }
  var run: Run { session.state.run }

  @ObservationIgnored private var reachedFor: (played: [String], on: Bool)?
  /// The game has been an endgame at some point, so its endgame rules are on.
  var endgameOn: Bool {
    if let reachedFor, reachedFor.played == run.played { return reachedFor.on }
    let on = endgameReached(run.played)
    reachedFor = (run.played, on)
    return on
  }
  var myTurn: Bool { playersTurn(session) }
  var live: Bool { phase == .playing && session.ending == nil }
  var prepNow: [String] { prepMoves(session) }
  var label: PrepLabel? { prepLabel(session) }
  /// The opening the run is named for.
  var openingId: String { run.enteredIn ?? round?.pick.opening.id ?? run.openingId }
  /// The header's name: a first game is named by the book as it goes.
  var headerName: String {
    if firstGame { return openingNameForPath(index, run.played)?.name ?? "My Playbook" }
    return openingName(tree, openingId)
  }
  var momentHere: Bool {
    prefs.moments && live && myTurn && pending == nil && prepNow.isEmpty && baseline?.fen == run.fen && baseline?.isMomentFor(run.color) == true
  }
  /// The board glows only while a moment is up.
  var glow: Glow? { momentHere ? MOMENT_GLOW : nil }

  /// The board as shown: your move stands while it is judged, a blunder stays until Continue.
  var shownFen: String {
    if held { return walkSan(introPath).fens[min(introPly, introPath.count)] }
    if let flash { return flash.move.after }
    if let pending { return pending.after }
    if case .blunder(let played, _, _, _, _) = session.ending, phase == .blunder { return applySan(run.fen, played)?.after ?? run.fen }
    return run.fen
  }

  /// The blunder and the threat that made it one.
  var blunder: (move: LegalMove, threat: LegalMove?)? {
    guard phase == .blunder, case .blunder(let played, _, _, let reply, _) = session.ending, let move = applySan(run.fen, played) else { return nil }
    return (move, reply.flatMap { applyUci(move.after, $0) })
  }

  /// A Middlegame run was announced while its handoff was built, so it goes straight to the board.
  func start() {
    if handoff != nil || firstGame { toBoard() } else { later(Self.announceMs) { $0.toBoard() } }
  }

  /// The announcement gives way to the board: the way in plays out, or the round begins.
  func toBoard() {
    guard intro == .announce else { return }
    intro = introPath.isEmpty ? .done : .replay
    intro == .done ? begin() : replayStep()
  }

  private func replayStep() {
    later(handoff != nil ? Self.handoffReplayMs : Self.replayMs) { model in
      guard model.intro == .replay else { return }
      if model.introPly < model.introPath.count {
        model.introPly += 1
        model.replayStep()
      } else {
        model.replayDone()
      }
    }
  }

  /// The way in has played out: a Middlegame run shows the structure's plan first, where it has one.
  private func replayDone() {
    introPly = introPath.count
    if handoff != nil && structureOf(run.fen) != nil {
      intro = .plan
      return
    }
    intro = .done
    pulseEdge()
    begin()
  }

  /// The plan card's Play: your clock starts.
  func playFromHandoff() {
    guard intro == .plan else { return }
    intro = .done
    pulseEdge()
    begin()
  }

  /// The board's edge pulses once the replay hands you the move.
  private(set) var pulse = false

  private func pulseEdge() {
    pulse = true
    later(Self.pulseMs) { $0.pulse = false }
  }

  /// A tap skips the rest of the replay.
  func skipIntro() {
    guard intro == .replay else { return }
    replayDone()
  }

  private func begin() {
    spanHeld = span
    advance()
  }

  func stop() {
    for task in tasks { task.cancel() }
    tasks.removeAll()
    reply?.search.cancel()
    reply = nil
  }

  /* ── turns ── */

  /// Whatever comes next: the opponent's reply, or your turn settled.
  private func advance() {
    guard live, !held else { return }
    if myTurn {
      beginTurn()
    } else if miss == nil {
      if fill != nil { fillReply() } else { opponent() }
    }
  }

  /// The opponent's own engine, so its reply can be searched while the judge
  /// weighs your move.
  private static let replyEngine = BasicEngine()
  /// The reply searched ahead, for the position after your move.
  private var reply: (fen: String, search: Task<EngineSnapshot, Never>)?

  /// Start searching the opponent's reply to your move straight away.
  private func searchReply(after fen: String) {
    reply?.search.cancel()
    let level = opponentLevel
    let engine = Self.replyEngine
    reply = (fen, Task { await engine.analyse(fen, EngineLimits(depth: level.depth, multiPv: level.multiPv)) })
  }

  private func opponent() {
    thinking = true
    spawn { [weak self] in
      try? await Task.sleep(for: .seconds(Self.replyMs))
      guard let self, !Task.isCancelled, self.live, !self.myTurn else { return }
      if self.tutorial, let san = firstGameReply(self.run.played) {
        self.thinking = false
        self.apply(engineMove(self.session, san))
        return
      }
      if let step = bookTurn(self.session, self.index, self.picker) {
        self.thinking = false
        self.apply(step)
        return
      }
      // The book has nothing: the engine plays the opponent.
      let fen = self.run.fen
      let level = self.opponentLevel
      let ready = self.reply.flatMap { $0.fen == fen ? $0.search : nil }
      self.reply = nil
      let snap: EngineSnapshot
      if let ready {
        snap = await ready.value
      } else {
        snap = await Self.replyEngine.analyse(fen, EngineLimits(depth: level.depth, multiPv: level.multiPv))
      }
      let san = chooseMove(snap.lines, level, self.picker).flatMap { applyUci(fen, $0)?.san }
      self.thinking = false
      guard !Task.isCancelled, self.live, self.run.fen == fen else { return }
      if let san {
        self.apply(engineMove(self.session, san))
      }
    }
  }

  /// Your turn begins: what the screen settles before you move.
  private func beginTurn() {
    turnStarted = Date()
    // Adding moves: the player picks the next one, nothing is weighed.
    if fill != nil {
      showTip()
      return
    }
    if prepNow.isEmpty { update(prepRanOut(session, index)) }
    update(closeBook(session, index))
    askAtHole()
    showTip()
    if fill != nil { return }
    // Past your prep the engine is sure to be asked: weigh the position now.
    if prepNow.isEmpty { weigh(run.fen) }
  }

  private func weigh(_ fen: String) {
    guard baseline?.fen != fen else { return }
    let moments = prefs.moments
    spawn { [weak self] in
      guard let self else { return }
      let base = await Engine.baseline(self.engine, fen, moments: moments)
      guard let base, !Task.isCancelled, self.live, self.run.fen == fen else { return }
      self.baseline = base
      self.update(sawEval(self.session, base.cp))
      if self.live && self.myTurn { self.update(missionFrom(self.session, self.prefs, base.cp)) }
      if self.momentHere { self.show(note: Note(text: "There's something here", tone: "accent")) }
    }
  }

  /// You played a move on the board. With the Undefended flash on, a move
  /// that leaves a piece loose is held a moment first, to take back.
  func play(_ move: LegalMove) {
    guard live, !held, myTurn, pending == nil, flash == nil else { return }
    if tip != nil { dismissTip() }
    if fill != nil {
      if fillChoices.contains(where: { $0.san == move.san }) { addMove(move.san) }
      return
    }
    // Your time stops when you move, not when a held move lands.
    let seconds = Date().timeIntervalSince(turnStarted)
    if prefs.undefendedFlash {
      let loose = newlyLoose(run.fen, move.after, run.color, from: move.from, to: move.to)
      if !loose.isEmpty {
        Haptics.buzz(12, on: store.state.settings.hapticFeedback)
        flashCount += 1
        let count = flashCount
        flash = (move, loose)
        later(Self.flashMs) { model in
          guard model.flash != nil, model.flashCount == count else { return }
          model.flash = nil
          model.commit(move, seconds: seconds)
        }
        return
      }
    }
    commit(move, seconds: seconds)
  }

  /// The flash's Take back: the held move never lands.
  func takeBack() { flash = nil }

  private func commit(_ move: LegalMove, seconds: Double) {
    guard live, !held, myTurn, pending == nil else { return }
    miss = nil
    note = nil
    missedBest = nil
    foundIt = false
    holeGap = nil
    if autoplayNote { store.update { $0.settings.seenAutoplayNote = true } }
    let now = Env.now()
    if prepNow.contains(move.san) {
      apply(playPrepared(session, ctx, move, seconds, now))
      return
    }
    pending = move
    searchReply(after: move.after)
    let fen = run.fen, color = run.color, moments = prefs.moments, reached = endgameOn
    spawn { [weak self] in
      guard let self else { return }
      var base = self.baseline?.fen == fen ? self.baseline : nil
      if base == nil { base = await Engine.baseline(self.engine, fen, moments: moments) }
      guard let base else {
        self.pending = nil
        return
      }
      let judged = await judge(self.engine, base, san: move.san, uci: move.uci, color: color, moments: moments, reached: reached)
      self.pending = nil
      // Ended while the judge was out: the move never counted.
      guard !Task.isCancelled, self.live, self.run.fen == fen else { return }
      self.store.update { $0.judgedMove(lost: judged.lost) }
      self.apply(judgedMove(self.session, self.ctx, judged, seconds, now))
    }
  }

  /* ── adding moves mid-run ── */

  /// At the run's one hole, ask the engine whether the line needs a new move now.
  private func askAtHole() {
    guard round != nil, !holeAsked, session.prepStatus == .complete, prepNow.isEmpty, session.state.misses.isEmpty,
      run.played.count > run.opened
    else { return }
    holeAsked = true
    guard let found = growAtHole(store.state, tree, selection, color: run.color, line: run.played) else { return }
    if found.yes { startFill(found.gap) } else { holeGap = found.gap }
  }

  /// The one-time note on autoplay: up while the first run that autoplays waits for your first move.
  var autoplayNote: Bool {
    round != nil && !store.state.settings.seenAutoplayNote && !introPath.isEmpty && session.state.moves == 0
  }

  /// The answers on offer while adding moves, the same as Growth's.
  var fillChoices: [Reply] { fill == nil ? [] : ranked }

  /// Add moves here, at the engine's word or the player's.
  func growHere() {
    guard let gap = holeGap, live, myTurn, pending == nil else { return }
    startFill(gap)
  }

  private func startFill(_ gap: Gap) {
    holeGap = nil
    fill = Fill(gap: gap, size: store.state.settings.movesPerFill)
    pulseEdge()
    store.update { $0.logEvent(AppEvent(kind: "inline-grow", via: .autopilot, color: gap.color, line: gap.line.joined(separator: " "))) }
  }

  /// A move picked while adding: saved to the Playbook, then played.
  func addMove(_ san: String) {
    guard var current = fill, live, myTurn, pending == nil else { return }
    if tip != nil { dismissTip() }
    let rid = current.gap.repertoireId
    let line = run.played + [san]
    let offered = fillChoices.map(\.san)
    let move = applySan(run.fen, san)
    // Undo removes from the first move this line added.
    let rep = store.state.repertoires[rid]
    let fresh = (1...line.count).first { k in rep.flatMap { nodeAtLine($0, Array(line.prefix(k))) } == nil } ?? line.count
    current.steps.append((session, Array(line.prefix(fresh))))
    filledRep = rid
    store.update { state in
      state.addGrowthLine(rid, line, index)
      state.logEvent(AppEvent(
        kind: "growth-pick", via: .autopilot, color: run.color, line: run.played.joined(separator: " "), picked: san, offered: offered))
    }
    Haptics.buzz(10, on: store.state.settings.hapticFeedback)
    fill = fillEnds(index, line, added: current.added, size: current.size) ? nil : current
    if fill == nil { holeGap = nil }
    justAdded = fill == nil ? nil : move.map { ($0.from, $0.to) }
    apply(playAdded(session, san))
  }

  /// The opponent's reply while adding moves: the book's most played, or the
  /// tutorial's set answer to move one.
  private func fillReply() {
    thinking = true
    later(Self.replyMs) { model in
      model.thinking = false
      guard model.live, !model.myTurn, model.fill != nil else { return }
      model.justAdded = nil
      let first = model.tutorial ? firstGameReply(model.run.played) : nil
      guard let san = first ?? popularReplies(model.index, model.run.fen, GAP_SHARE).first?.san else {
        model.fill = nil
        model.advance()
        return
      }
      model.apply(playFillReply(model.session, san))
    }
  }

  /// Undo while adding: the last move added comes out of the Playbook and off the board.
  func undoAdded() {
    guard var current = fill, !current.steps.isEmpty else { return }
    let last = current.steps.removeLast()
    let rid = current.gap.repertoireId
    stop()
    thinking = false
    store.update { state in
      if let rep = state.repertoires[rid], let node = nodeAtLine(rep, last.remove) { _ = state.removeNode(rid, node.id, via: .autopilot) }
    }
    session = last.session
    justAdded = nil
    fill = current
  }

  /* ── the first game's tips ── */

  /// The tip for where the first game stands, if one is still to show there.
  private func showTip() {
    guard firstGame, tip == nil, live, myTurn else { return }
    let pending = store.state.settings.tips
    let moment: FirstGameMoment? =
      if fill != nil { .adding(ply: run.played.count) }
      else if filledRep != nil && pending.contains(.lineIn) { .lineIn }
      else if label == .book { .book }
      else if label == .out { .outOfBook }
      else { nil }
    guard let moment, let found = tipAt(pending, moment) else { return }
    tip = found.tip
    store.update { $0.settings.tips = found.rest }
  }

  /// A tap on the tip, or your next move: out of the book, the lenses' tip follows.
  func dismissTip() {
    let next = store.state.settings.tips.first
    if tip == .outOfBook && next == .lens {
      tip = .lens
      store.update { _ = $0.settings.tips.removeFirst() }
    } else {
      tip = nil
    }
  }

  /// The goal card waits until the first game's tips in play are done.
  var tipsInPlay: Bool {
    firstGame && (tip?.inGame == true || store.state.settings.tips.contains { $0.inGame })
  }

  /// Done: no more moves added, and the game goes on from here.
  func doneAdding() {
    guard fill != nil else { return }
    fill = nil
    justAdded = nil
    advance()
  }

  /// You ended the round.
  func endRound() {
    guard finish == nil else { return }
    stop()
    pending = nil
    flash = nil
    apply(endRun(session))
  }

  /// Past the blunder, on to the end screen.
  func continueToEnd() { phase = .over }

  /* ── the controller's steps ── */

  private func update(_ next: RunSession) {
    session = next
    if session.prepStatus != .off { spanHeld = span }
  }

  private func apply(_ step: Step) {
    if step.session.prepStatus == .off && session.prepStatus != .off { spanHeld = span }
    session = step.session
    for effect in step.effects {
      switch effect {
      case .rate(let result, let earlier):
        var moves: [RatingMove] = []
        store.update { moves = $0.recordMove(tree, result, earlier) }
        ratings.track(moves)
      case .answered(let rid, let fen, let san, let grade):
        store.update { $0.answered(rid, fen, san, grade) }
      case .missed(let rid, let fen, let played, let expected):
        store.update { $0.missed(rid, fen, played, expected) }
      case .buzz(let pattern):
        Haptics.buzz(pattern, on: store.state.settings.hapticFeedback)
      case .pop(let p):
        show(pop: p)
      case .note(let n):
        if let n { show(note: n) } else { note = nil }
      case .miss(let m):
        show(miss: m)
      case .moment(let found):
        foundIt = found
        if found { Haptics.success(on: store.state.settings.hapticFeedback) }
        pulse(found: found)
      case .missedBest(let move):
        missedBest = move
      case .finish(let f):
        finished(f)
      }
    }
    advance()
  }

  private func finished(_ f: Finish) {
    stop()
    finish = f
    if firstGame, let found = tipAt(store.state.settings.tips, .end) {
      tip = found.tip
      store.update { $0.settings.tips = found.rest }
    } else if firstGame {
      tip = nil
    }
    before = handoff != nil ? store.state.middlegame : store.state.survival
    let line = f.ended.run.played
    let points = scoredInPoints ? f.ended.extras.points : f.ended.moves
    // An endgame result that slipped away is kept for Endgame mode, from the position before the move.
    let given = endgameGivenAway(f.how, fen: f.ended.run.fen, name: openingName(tree, f.ended.run.openingId), at: Env.now())
    // Built before the update: reading the store inside its own update is an exclusivity crash.
    let record = game(f)
    store.update { $0.recordGame(record) }
    if let handoff {
      // Counted against the openings your own line went through. No prep was asked, so no rating or card moves.
      let yours = Array(handoff.line.prefix(handoff.prep))
      store.update { state in
        if case .ended = f.how { state.endMiddlegameEarly(tree, yours) } else { state.endMiddlegame(tree, yours, points) }
        if let given { state.endgames.save(given) }
      }
      settle(f)
      return
    }
    store.update { state in
      if case .ended = f.how {
        state.endSurvivalEarly(tree, line)
      } else {
        state.endSurvival(tree, line, f.ended.moves, points)
      }
      ratings.track(state.settleRun(tree, f.answers, line))
      state.endRound(tree, runRound(f, tree, at: Env.now()))
      if let given { state.endgames.save(given) }
    }
    settle(f)
  }

  /// The run as a game for the history.
  private func game(_ f: Finish) -> GameRecord {
    let run = f.ended.run
    let outcome = runOutcome(f.how, color: run.color)
    let mode: GameMode = handoff != nil ? .middlegame : round != nil ? .autopilot : .survival
    return GameRecord(
      id: run.id, mode: mode, at: Env.now(), color: run.color, picked: pickedFor(selection, saved: store.state.settings.selection),
      opening: run.openingId, moves: run.played, opened: run.opened, result: outcome.result, termination: outcome.termination)
  }

  /// What floats over the board goes, and the blunder or the end screen comes up.
  private func settle(_ f: Finish) {
    pop = nil
    note = nil
    miss = nil
    flash = nil
    thinking = false
    if case .blunder = f.how {
      Haptics.buzz(22, on: store.state.settings.hapticFeedback)
      phase = .blunder
    } else {
      phase = .over
    }
  }

  /* ── what floats over the board ── */

  private func show(pop p: Pop) {
    pop = p
    later(Self.scoreMs) { model in
      if model.pop == p { model.pop = nil }
    }
  }

  private func show(note n: Note) {
    note = n
    later(Self.noteMs) { model in
      if model.note == n { model.note = nil }
    }
  }

  private func pulse(found: Bool) {
    let id = (edgePulse?.id ?? 0) + 1
    edgePulse = (found, id)
    later(Self.edgePulseMs) { model in
      if model.edgePulse?.id == id { model.edgePulse = nil }
    }
  }

  private func show(miss m: MissFlash) {
    miss = m
    later(Self.missMs) { model in
      guard model.miss == m else { return }
      model.miss = nil
      model.advance()
    }
  }

  /// A touch anywhere clears a miss or a note sooner. The missed moment's squares stay.
  func clearOverlays() {
    note = nil
    guard miss != nil else { return }
    miss = nil
    advance()
  }

  private func later(_ seconds: Double, _ then: @escaping @MainActor (RunModel) -> Void) {
    spawn { [weak self] in
      try? await Task.sleep(for: .seconds(seconds))
      if let self, !Task.isCancelled { then(self) }
    }
  }

  private func spawn(_ work: @escaping @MainActor () async -> Void) {
    tasks.removeAll { $0.isCancelled }
    tasks.append(Task { @MainActor in await work() })
  }
}

/// Each opening's rating over a run: where it stood before its first move, and after its last.
/// `byKey` holds the main ratings; `changes` lists Extensions ratings too, in the order first moved.
struct OrderedRatings {
  struct Change {
    var id: String
    var ext: Bool
    var before: Double
    var after: Double
    var delta: Double { after - before }
  }

  private(set) var changes: [Change] = []

  var byKey: [String: (before: Double, after: Double)] {
    Dictionary(changes.filter { !$0.ext }.map { ($0.id, ($0.before, $0.after)) }, uniquingKeysWith: { a, _ in a })
  }

  mutating func track(_ moves: [RatingMove]) {
    for move in moves {
      if let i = changes.firstIndex(where: { $0.id == move.id && $0.ext == move.ext }) {
        changes[i].after = move.after
      } else {
        changes.append(Change(id: move.id, ext: move.ext, before: move.before, after: move.after))
      }
    }
  }
}

extension RunModel: HoleAnswers {
  var atHole: Bool { fill != nil && live && myTurn }
  var holeFen: String { run.fen }
  var holePath: [String] { run.played }
  var answerColor: ChessCore.Color { run.color }
  var answerTree: Repertoire? { fill.flatMap { store.state.repertoires[$0.gap.repertoireId] } }
  var nudgePrefs: NudgePrefs {
    let prefs = store.state.settings.growth
    return NudgePrefs(priority: prefs.nudgePriority, pawns: prefs.nudgePawns)
  }
  /// A fill answers gaps, so it offers what a gap's Growth sitting would.
  var minShare: Double { GAP_SHARE }
}
