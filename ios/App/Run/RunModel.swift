import Book
import ChessCore
import Engine
import Foundation
import Model
import Observation

/// One Autopilot run on screen: `SurvivalScreen.tsx`'s job. It feeds the
/// controller what happens (your moves, the judge's verdicts, the
/// opponent's replies), carries out the effects in order, and keeps what
/// the view draws.
@MainActor @Observable
final class RunModel {
  enum Phase { case playing, blunder, over }

  /// How long a miss, a score popup and a note stay over the board; the opponent's beat.
  static let missMs = 2.0, scoreMs = 1.4, noteMs = 1.6, replyMs = 0.42

  let round: AutoRound
  let selection: Selection
  let tree: OpeningTree
  let index: ReferenceIndex
  private let store: AppStore
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

  private var picker: () -> Double
  private var turnStarted = Date()
  private var tasks: [Task<Void, Never>] = []

  init?(round: AutoRound, selection: Selection, store: AppStore, tree: OpeningTree, index: ReferenceIndex, engine: ChessEngine) {
    let seed = (Env.random() * 2_147_483_648).rounded(.down)
    guard let begun = startSurvival(survivalOptions(round, store.state, tree, selection, seed: seed)) else { return nil }
    self.round = round
    self.selection = selection
    self.store = store
    self.tree = tree
    self.index = index
    self.engine = engine
    picker = mulberry32(seed: (Env.random() * 2_147_483_648).rounded(.down))
    session = beginSession(begun)
    let prefs = autoSurvival(store.state.settings.autopilot)
    let losses = lossesIn(store.state.repertoireList)
    ctx = RunContext(
      index: index, prefs: prefs, autopilot: true,
      kindOf: { line, san in playedKinds(index, line + [san], line.count % 2 == 0 ? .w : .b, losses).last ?? .book },
      lossOf: { losses[$0] })
    store.update { $0.noteStart(startKind(start: round.pick.start, at: round.at)) }
  }

  var prefs: SurvivalPrefs { ctx.prefs }
  var run: Run { session.state.run }
  var myTurn: Bool { playersTurn(session) }
  var live: Bool { phase == .playing && session.ending == nil }
  var prepNow: [String] { prepMoves(session) }
  var label: PrepLabel? { prepLabel(session) }
  /// The opening the run is named for.
  var openingId: String { run.enteredIn ?? round.pick.opening.id }
  var momentHere: Bool {
    prefs.moments && live && myTurn && pending == nil && prepNow.isEmpty && baseline?.fen == run.fen && baseline?.isMomentFor(run.color) == true
  }
  var glow: Glow? { prefs.boardGlow ? session.evalCp.map { glowFor(run.color, $0) } ?? nil : nil }

  /// The board as shown: your move stands while it is judged, a blunder stays until Continue.
  var shownFen: String {
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

  func start() { advance() }

  func stop() {
    for task in tasks { task.cancel() }
    tasks.removeAll()
  }

  /* ── turns ── */

  /// Whatever comes next: the opponent's reply, or your turn settled.
  private func advance() {
    guard live else { return }
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

  /// You played a move on the board.
  func play(_ move: LegalMove) {
    guard live, myTurn, pending == nil else { return }
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
    apply(endRun(session))
  }

  /// Past the blunder, on to the end screen.
  func continueToEnd() { phase = .over }

  /* ── the controller's steps ── */

  private func update(_ next: RunSession) {
    session = next
  }

  private func apply(_ step: Step) {
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
    let line = f.ended.run.played
    store.update { state in
      if case .ended = f.how {
        state.endSurvivalEarly(tree, line)
      } else {
        state.endSurvival(tree, line, f.ended.moves, f.ended.extras.points)
      }
      ratings.track(state.settleRun(tree, f.answers, line))
      state.endRound(tree, runRound(f, tree, at: Env.now()))
    }
    offer = offerFor(store.state, tree, index, f, region: f.ended.run.openingId)
    pop = nil
    note = nil
    miss = nil
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
struct OrderedRatings {
  private(set) var order: [String] = []
  private(set) var byKey: [String: (before: Double, after: Double)] = [:]

  mutating func track(_ moves: [RatingMove]) {
    for move in moves where !move.ext {
      if let seen = byKey[move.id] {
        byKey[move.id] = (seen.before, move.after)
      } else {
        order.append(move.id)
        byKey[move.id] = (move.before, move.after)
      }
    }
  }
}
