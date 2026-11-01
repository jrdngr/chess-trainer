import Book
import ChessCore
import Engine
import Foundation
import Model
import Observation

/// One Survival run on screen, Autopilot's or one you set up: `SurvivalScreen.tsx`'s
/// job. It feeds the controller what happens (your moves, the judge's verdicts,
/// the opponent's replies), carries out the effects in order, and keeps what
/// the view draws.
@MainActor @Observable
final class RunModel {
  enum Phase { case playing, blunder, over }
  /// The round's intro: announced full screen, then the way in played out on a locked board.
  enum Intro { case announce, replay, done }

  /// How long the announcement holds, and the beat between replayed moves: `RoundIntro.tsx`.
  static let announceMs = 2.5, replayMs = 0.4, pulseMs = 0.9

  /// How long a miss, a score popup and a note stay over the board; the opponent's beat.
  static let missMs = 2.0, scoreMs = 1.4, noteMs = 1.6, replyMs = 0.42
  /// How long the Undefended flash holds your move before it lands.
  static let flashMs = 1.3

  /// Autopilot's round; nil for a run set up on Survival's own screen.
  let round: AutoRound?
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
  private(set) var missedBest: (from: String, to: String)?
  /// Your move, on the board while the engine judges it.
  private(set) var pending: LegalMove?
  private(set) var thinking = false
  private(set) var baseline: Baseline?
  /// Each opening's rating this run: where it stood before, and where it is now.
  private(set) var ratings = OrderedRatings()
  private(set) var finish: Finish?
  /// The way into Growth a clean end of prep earns.
  private(set) var offer: GrowOffer?
  private(set) var intro = Intro.announce
  /// How many of the way in's moves the replay has played.
  private(set) var introPly = 0
  private var spanHeld: PrepSpan?
  /// A move held back by the Undefended flash: what it leaves loose.
  private(set) var flash: (move: LegalMove, loose: [String])?
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

  /// A run set up on Survival's screen, on those options: `start` with no plan.
  convenience init?(survival options: StartOptions, prefs: SurvivalPrefs, growth: GrowthPrefs, selection: Selection,
                    store: AppStore, tree: OpeningTree, index: ReferenceIndex, engine: ChessEngine) {
    guard let begun = startSurvival(options) else { return nil }
    self.init(begun: begun, round: nil, prefs: prefs, growth: growth, selection: selection, store: store, tree: tree, index: index, engine: engine)
  }

  private init(begun: SurvivalStart, round: AutoRound?, prefs: SurvivalPrefs, growth: GrowthPrefs, selection: Selection,
               store: AppStore, tree: OpeningTree, index: ReferenceIndex, engine: ChessEngine) {
    self.round = round
    self.selection = selection
    self.store = store
    self.tree = tree
    self.index = index
    self.engine = engine
    self.growth = growth
    picker = mulberry32(seed: (Env.random() * 2_147_483_648).rounded(.down))
    session = beginSession(begun)
    let losses = lossesIn(store.state.repertoireList)
    ctx = RunContext(
      index: index, prefs: prefs, autopilot: round != nil,
      kindOf: { line, san in playedKinds(index, line + [san], line.count % 2 == 0 ? .w : .b, losses).last ?? .book },
      lossOf: { losses[$0] })
  }

  var prefs: SurvivalPrefs { ctx.prefs }
  /// With moments, missions or the combo on, a run is scored in points as well as moves.
  var scoredInPoints: Bool { prefs.moments || prefs.missions || prefs.combo }
  /// Announcing or replaying: the board is locked, and the opponent waits.
  var held: Bool { intro != .done }
  /// The moves the intro plays out: the way in, with Autoplay on.
  var introPath: [String] { store.state.settings.autoplay ? Array(run.played.prefix(run.opened)) : [] }
  /// The opening the round is announced as. A run from move one is named by the opening it is steered toward.
  var introOpening: String {
    run.enteredIn ?? round?.pick.opening.id
      ?? deepestNodeWithin(tree, nodeById(tree, run.openingId), Array(run.played.prefix(run.opened))).id
  }

  /// How far into your prep the run stands, out of how far it goes along this line. Held once off prep.
  var span: PrepSpan? {
    if session.prepStatus == .off { return spanHeld }
    let line = run.played + continuation(session.source, run)
    let total = prepDepth(line, run.color, session.source.prepAt, run.opened)
    let book = session.prepStatus == .complete && session.bookTo != nil ? max(0, session.bookTo! - total) : 0
    let losses = lossesIn(store.state.repertoireList)
    let ext = bookLength(playedKinds(index, Array(line.prefix(total)), run.color, losses))
    return PrepSpan(played: min(run.played.count, total), total: total, book: book > 0 ? book : nil, ext: ext < total ? ext : nil)
  }
  var run: Run { session.state.run }
  var myTurn: Bool { playersTurn(session) }
  var live: Bool { phase == .playing && session.ending == nil }
  var prepNow: [String] { prepMoves(session) }
  var label: PrepLabel? { prepLabel(session) }
  /// The opening the run is named for.
  var openingId: String { run.enteredIn ?? round?.pick.opening.id ?? run.openingId }
  var momentHere: Bool {
    prefs.moments && live && myTurn && pending == nil && prepNow.isEmpty && baseline?.fen == run.fen && baseline?.isMomentFor(run.color) == true
  }
  var glow: Glow? { prefs.boardGlow ? session.evalCp.map { glowFor(run.color, $0) } ?? nil : nil }

  /// The board as shown: your move stands while it is judged, a blunder stays until Continue.
  var shownFen: String {
    if held { return walkSan(introPath).fens[min(introPly, introPath.count)] }
    if let flash { return flash.move.after }
    if let pending { return pending.after }
    if case .blunder(let played, _, _, _) = session.ending, phase == .blunder { return applySan(run.fen, played)?.after ?? run.fen }
    return run.fen
  }

  /// The blunder and the threat that made it one.
  var blunder: (move: LegalMove, threat: LegalMove?)? {
    guard phase == .blunder, case .blunder(let played, _, _, let reply) = session.ending, let move = applySan(run.fen, played) else { return nil }
    return (move, reply.flatMap { applyUci(move.after, $0) })
  }

  /// What this run has done to the opening's own rating.
  var ratingGained: Double {
    guard let r = ratings.byKey[openingId] else { return 0 }
    return r.after - r.before
  }

  func start() {
    later(Self.announceMs) { $0.toBoard() }
  }

  /// The announcement gives way to the board: the way in plays out, or the round begins.
  func toBoard() {
    guard intro == .announce else { return }
    intro = introPath.isEmpty ? .done : .replay
    intro == .done ? begin() : replayStep()
  }

  private func replayStep() {
    later(Self.replayMs) { model in
      guard model.intro == .replay else { return }
      if model.introPly < model.introPath.count {
        model.introPly += 1
        model.replayStep()
      } else {
        model.intro = .done
        model.pulseEdge()
        model.begin()
      }
    }
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
    introPly = introPath.count
    intro = .done
    pulseEdge()
    begin()
  }

  private func begin() {
    spanHeld = span
    advance()
  }

  func stop() {
    for task in tasks { task.cancel() }
    tasks.removeAll()
  }

  /* ── turns ── */

  /// Whatever comes next: the opponent's reply, or your turn settled.
  private func advance() {
    guard live, !held else { return }
    if myTurn {
      beginTurn()
    } else if miss == nil {
      opponent()
    }
  }

  private func opponent() {
    thinking = true
    spawn { [weak self] in
      try? await Task.sleep(for: .seconds(Self.replyMs))
      guard let self, self.live, !self.myTurn else { return }
      if let step = bookTurn(self.session, self.index, self.picker) {
        self.thinking = false
        self.apply(step)
        return
      }
      // The book has nothing: the engine plays the opponent.
      let fen = self.run.fen
      let snap = await self.engine.analyse(fen, EngineLimits(depth: OPPONENT_LEVEL.depth, multiPv: OPPONENT_LEVEL.multiPv))
      let san = chooseMove(snap.lines, OPPONENT_LEVEL, self.picker).flatMap { applyUci(fen, $0)?.san }
      self.thinking = false
      guard self.live, self.run.fen == fen else { return }
      if let san {
        self.apply(engineMove(self.session, san))
      }
    }
  }

  /// Your turn begins: what the screen settles before you move.
  private func beginTurn() {
    turnStarted = Date()
    if prepNow.isEmpty { update(prepRanOut(session, index)) }
    update(closeBook(session, index))
    // Past your prep the engine is sure to be asked: weigh the position now.
    if prepNow.isEmpty { weigh(run.fen) }
  }

  private func weigh(_ fen: String) {
    guard baseline?.fen != fen else { return }
    let moments = prefs.moments
    spawn { [weak self] in
      guard let self else { return }
      let base = await Engine.baseline(self.engine, fen, moments: moments)
      guard let base, self.run.fen == fen else { return }
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
    if prefs.undefendedFlash {
      let loose = newlyLoose(run.fen, move.after, run.color, from: move.from, to: move.to)
      if !loose.isEmpty {
        Haptics.buzz(12, on: store.state.settings.hapticFeedback)
        flash = (move, loose)
        later(Self.flashMs) { model in
          guard let held = model.flash, held.move.uci == move.uci else { return }
          model.flash = nil
          model.commit(move)
        }
        return
      }
    }
    commit(move)
  }

  /// The flash's Take back: the held move never lands.
  func takeBack() { flash = nil }

  private func commit(_ move: LegalMove) {
    guard live, !held, myTurn, pending == nil else { return }
    miss = nil
    let seconds = Date().timeIntervalSince(turnStarted)
    let now = Env.now()
    if prepNow.contains(move.san) {
      apply(playPrepared(session, ctx, move, seconds, now))
      return
    }
    pending = move
    let fen = run.fen, color = run.color, moments = prefs.moments
    spawn { [weak self] in
      guard let self else { return }
      var base = self.baseline?.fen == fen ? self.baseline : nil
      if base == nil { base = await Engine.baseline(self.engine, fen, moments: moments) }
      guard let base else {
        self.pending = nil
        return
      }
      let judged = await judge(self.engine, base, san: move.san, uci: move.uci, color: color, moments: moments)
      self.pending = nil
      guard self.run.fen == fen else { return }
      self.apply(judgedMove(self.session, self.ctx, judged, seconds, now))
    }
  }

  /// You ended the round.
  func endRound() {
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
    before = store.state.survival
    let line = f.ended.run.played
    let points = scoredInPoints ? f.ended.extras.points : f.ended.moves
    store.update { state in
      if case .ended = f.how {
        state.endSurvivalEarly(tree, line)
      } else {
        state.endSurvival(tree, line, f.ended.moves, points)
      }
      ratings.track(state.settleRun(tree, f.answers, line))
      state.endRound(tree, runRound(f, tree, at: Env.now()))
    }
    offer = offerFor(store.state, tree, index, f, region: f.ended.run.openingId, growth: growth)
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
      guard model.note == n else { return }
      model.note = nil
      model.missedBest = nil
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

  /// A tap on the board clears a miss sooner.
  func clearMiss() {
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
