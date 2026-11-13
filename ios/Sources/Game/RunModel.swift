import Book
import ChessCore
import Engine
import Foundation
import Model
import Observation

/// One run on screen, Play's or one you set up. It feeds the controller what happens (your moves, the judge's verdicts,
/// the opponent's replies), carries out the effects in order, and keeps what
/// the view draws.
@MainActor @Observable
public final class RunModel {
  public enum Phase { case playing, blunder, over }
  /// The round's intro: announced full screen (Play deals the round's card, which grows into the board),
  /// then for a Middlegame run the handoff played out on a locked board. A Play run replays its way in only
  /// when asked (Replay moves).
  /// A Middlegame run then shows the plan card at the handoff before your clock starts.
  public enum Intro { case announce, replay, plan, done }

  /// How long the announcement holds (Play's deal takes `GameServices.dealSeconds`), and the beat between replayed moves (a Middlegame run's is quicker).
  public static let announceMs = 1.2, replayMs = 0.4, handoffReplayMs = 0.12, pulseMs = 0.9

  /// How long a miss and a score popup stay over the board (a touch clears a miss sooner); the opponent's beat.
  public static let missMs = 2.0, scoreMs = 1.4, replyMs = 0.42
  /// How long the board's edge pulses when a moment is settled.
  public static let edgePulseMs = 1.5
  /// How long the Undefended flash holds your move before it lands.
  public static let flashMs = 1.3

  /// Play's round; nil for a run set up on Run's or Middlegame's own screen.
  public let round: AutoRound?
  /// A Middlegame run's handoff: the moves played for you, and who chose each.
  public let handoff: Handoff?
  public let selection: Selection
  public let tree: OpeningTree
  public let index: ReferenceIndex
  private let store: AppStore
  private let engine: ChessEngine
  private let ctx: RunContext

  public private(set) var session: RunSession
  public private(set) var phase = Phase.playing
  public private(set) var pop: Pop?
  public private(set) var miss: MissFlash?
  /// The moment's move you missed: its squares stay red until your next move.
  public private(set) var missedBest: (from: String, to: String)?
  /// The board's edge pulsing for a moment settled: green found, red missed. `id` restarts it.
  public private(set) var edgePulse: (found: Bool, id: Int)?
  /// Your move, on the board while the engine judges it.
  public private(set) var pending: LegalMove?
  public private(set) var thinking = false
  public private(set) var baseline: Baseline?
  /// Each opening's rating this run: where it stood before, and where it is now.
  public private(set) var ratings = OrderedRatings()
  public private(set) var finish: Finish?
  /// The end screen has opened once: its verdict and rating change have played, and stay at rest after.
  public var endSeen = false
  /// Moves being added to the Playbook mid-run, at the gap the run reached.
  public struct Fill {
    public var gap: Gap
    public var size: Int
    /// Each move added: the run before it, and the line whose node Undo removes.
    public var steps: [(session: RunSession, remove: [String])] = []
    public var added: Int { steps.count }
  }
  public private(set) var fill: Fill?
  /// The move just added while adding moves, green on the board until their reply.
  public private(set) var justAdded: (from: String, to: String)?
  @ObservationIgnored public let tonedMemo = Memo<[NudgedMove]>()
  /// The gap the run reached when the engine said no new move: the player can
  /// still add one while it is their move there.
  public private(set) var holeGap: Gap?
  /// The run has reached its one hole and asked about it.
  private var holeAsked = false
  /// A new player's first game: nothing saved, adding moves from move one, with tips.
  public private(set) var firstGame = false
  /// A Play run filling a Black basic from move one.
  public private(set) var basicRun = false
  /// A tutorial game, and the line it is on: your opening, with the moves its growth added.
  public private(set) var tutorialGame: TutorialGame?
  public private(set) var tutorialLine: [String] = []
  /// The tutorial game's growth has begun, and has just ended.
  private var tutorialGrown = false
  private var tutorialJustGrown = false
  /// Your moves the engine scored in a tutorial game.
  private var tutorialScored = 0
  /// The tutorial game asks you to end it with the X: the board takes no more moves.
  public private(set) var endCued = false
  /// The tutorial's tip on screen.
  public private(set) var tip: TutorialTip?
  /// The side's Playbook that moves were added to this run.
  private var filledRep: String?
  public private(set) var intro = Intro.announce
  /// How many of the way in's moves the replay has played.
  public private(set) var introPly = 0
  private var spanHeld: PrepSpan?
  /// A move held back by the Undefended flash: what it leaves loose.
  public private(set) var flash: (move: LegalMove, loose: [String])?
  /// Counts held moves, so a flash's timer lands only the hold it began with.
  private var flashCount = 0
  /// The Run record as it stood before this run ended, to tell a new best.
  public private(set) var before: RunRecord?

  private var picker: () -> Double
  /// When your turn began: the clock counts from here.
  public private(set) var turnStartedAt: Double
  /// When your turn began, as a date for the clock on screen.
  public var turnStarted: Date { Date(timeIntervalSince1970: turnStartedAt) }
  /// When the app left the screen; time away doesn't count against your move.
  private var awaySince: Double?
  /// Counts popups, so each one floats up once however the board changes under it.
  public private(set) var popCount = 0
  private var tasks: [Task<Void, Never>] = []
  /// What a clean end of prep grows with.
  private let growth: GrowthPrefs

  /// Play's round, on Play's own options.
  /// A round that grows at a first move (Black's answer to 1.e4 or 1.d4) adds it before the game goes on.
  public convenience init?(round: AutoRound, selection: Selection, store: AppStore, tree: OpeningTree, index: ReferenceIndex, engine: ChessEngine) {
    let first = round.grow.flatMap { $0.hole.path.isEmpty ? $0 : nil }
    var repId = ""
    if let first { store.update { repId = $0.ensurePlaybook(first.color) } }
    let seed = (Env.random() * 2_147_483_648).rounded(.down)
    guard let begun = startRun(runOptions(round, store.state, tree, selection, seed: seed)) else { return nil }
    self.init(
      begun: begun, round: round, prefs: autoRun(store.state.settings.play), growth: AUTO_GROWTH,
      selection: selection, store: store, tree: tree, index: index, engine: engine)
    if var first {
      first.playbookId = repId
      basicRun = true
      holeAsked = true
      fill = Fill(gap: first, size: store.state.settings.movesPerFill)
    }
  }

  /// A new player's first game: White, nothing saved, adding moves from move one.
  public convenience init?(firstGame store: AppStore, tree: OpeningTree, index: ReferenceIndex, engine: ChessEngine) {
    var repId = ""
    store.update { repId = $0.ensurePlaybook(.w) }
    guard let rep = store.state.playbooks[repId] else { return nil }
    self.init(
      round: firstGameRound(tree), selection: Selection(color: .w, opening: ANY_OPENING), store: store, tree: tree, index: index,
      engine: engine)
    firstGame = true
    holeAsked = true
    fill = Fill(gap: firstMoveGap(rep, index), size: store.state.settings.movesPerFill)
  }

  /// One of the tutorial's games: its side from move one, its moves forced
  /// where it says, the opponent along its line and script.
  public convenience init?(tutorial game: TutorialGame, store: AppStore, tree: OpeningTree, index: ReferenceIndex, engine: ChessEngine) {
    store.update { _ = $0.ensurePlaybook(game.color) }
    self.init(
      round: tutorialRound(tree, game), selection: Selection(color: game.color == .w ? .w : .b, opening: ANY_OPENING),
      store: store, tree: tree, index: index, engine: engine)
    tutorialGame = game
    tutorialLine = game.opening.sans
    holeAsked = true
    store.update { $0.settings.tips = game.tips }
  }

  /// A run set up on Run's screen, on those options: `start` with no plan.
  public convenience init?(run options: StartOptions, prefs: RunPrefs, growth: GrowthPrefs, selection: Selection,
                    store: AppStore, tree: OpeningTree, index: ReferenceIndex, engine: ChessEngine) {
    guard let begun = startRun(options) else { return nil }
    self.init(begun: begun, round: nil, prefs: prefs, growth: growth, selection: selection, store: store, tree: tree, index: index, engine: engine)
  }

  /// A Middlegame run, begun at its handoff: `options` start at `handoff.line`.
  public convenience init?(middlegame options: StartOptions, handoff: Handoff, prefs: RunPrefs, selection: Selection,
                    store: AppStore, tree: OpeningTree, index: ReferenceIndex, engine: ChessEngine) {
    var options = options
    options.at = handoff.line
    guard let begun = startRun(options), begun.state.run.played == handoff.line else { return nil }
    self.init(
      begun: begun, round: nil, handoff: handoff, prefs: middlegamePrefs(prefs), growth: store.state.settings.growth,
      selection: selection, store: store, tree: tree, index: index, engine: engine)
  }

  private init(begun: RunBegun, round: AutoRound?, handoff: Handoff? = nil, prefs: RunPrefs, growth: GrowthPrefs, selection: Selection,
               store: AppStore, tree: OpeningTree, index: ReferenceIndex, engine: ChessEngine) {
    self.round = round
    self.handoff = handoff
    self.selection = selection
    self.store = store
    self.tree = tree
    self.index = index
    self.engine = engine
    self.growth = growth
    turnStartedAt = store.services.clock.now
    picker = mulberry32(seed: (Env.random() * 2_147_483_648).rounded(.down))
    session = handoff != nil ? beginMiddlegame(begun) : beginSession(begun)
    ctx = RunContext(index: index, prefs: prefs, play: round != nil)
  }

  public var prefs: RunPrefs { ctx.prefs }
  public var services: GameServices { store.services }
  private var now: Double { services.clock.now }
  /// Who plays the other side past the book. Play's opponent always plays at your strength.
  public var opponentLevel: Level {
    round != nil ? levelMatching(store.state.strength) : prefs.opponentLevel(store.state.strength)
  }
  /// With moments, missions or the combo on, a run is scored in points as well as moves.
  public var scoredInPoints: Bool { prefs.moments || prefs.missions || prefs.combo }
  /// Announcing or replaying: the board is locked, and the opponent waits.
  public var held: Bool { intro != .done }
  /// The moves the intro plays out: a Middlegame run's handoff always; a Play run's way in when Replay moves asks.
  public var introPath: [String] { handoff != nil || replaying ? Array(run.played.prefix(run.opened)) : [] }
  /// Replay moves was tapped: the way in plays out from move one, then the board is handed back.
  public private(set) var replaying = false

  /// Replay moves is on offer: a Play run started inside its line, until your first move.
  public var canReplay: Bool {
    round != nil && run.opened > 0 && intro == .done && live && myTurn && session.state.moves == 0 && fill == nil && pending == nil
  }

  /// Replay moves: the board goes back to move one and the way in plays out, as the intro used to.
  public func replayMoves() {
    guard canReplay else { return }
    replaying = true
    introPly = 0
    intro = .replay
    replayStep()
  }
  /// The opening the round is announced as. A run from move one is named by the opening it is steered toward.
  /// Under Any Opening it is the opening of the line drawn, never Any Opening itself.
  public var introOpening: String {
    let named = run.enteredIn ?? round?.pick.opening.id
      ?? deepestNodeWithin(tree, nodeById(tree, run.openingId), Array(run.played.prefix(run.opened))).id
    let node = nodeById(tree, named)
    return node.depth == 0 ? deepestNodeWithin(tree, node, run.drawn).id : named
  }

  /// How far into your prep the run stands, out of how far it goes along this line, in your own moves. Held once off prep.
  /// None for a Freeform Play run, which always starts from move one.
  public var span: PrepSpan? {
    if round?.free == true { return nil }
    if session.prepStatus == .off { return spanHeld }
    let line = run.played + continuation(session.source, run)
    // Moves added this run are prep too, though the run's source was read before them.
    let added = filledRep.map { prepIndex(store.state.playbooks[$0]) } ?? [:]
    let prepAt = filledRep != nil ? { (fen: String) in added[positionKey(fen)] ?? [] } : session.source.prepAt
    let total = prepDepth(line, run.color, prepAt, run.opened)
    // Common moves past your line aren't counted on the bar: scores start where your line ends.
    return PrepSpan(played: min(run.played.count, total), total: total, book: nil).ownMoves(run.color)
  }
  public var run: Run { session.state.run }

  @ObservationIgnored private var reachedFor: (played: [String], on: Bool)?
  /// The game has been an endgame at some point, so its endgame rules are on.
  public var endgameOn: Bool {
    if let reachedFor, reachedFor.played == run.played { return reachedFor.on }
    let on = endgameReached(run.played)
    reachedFor = (run.played, on)
    return on
  }
  public var myTurn: Bool { playersTurn(session) }
  public var live: Bool { phase == .playing && session.ending == nil }
  public var prepNow: [String] { prepMoves(session) }
  public var label: PrepLabel? { prepLabel(session) }
  /// The opening the run is named for.
  public var openingId: String { run.enteredIn ?? round?.pick.opening.id ?? run.openingId }
  /// The header's name: a first game is named by the book as it goes.
  public var headerName: String {
    if let tutorialGame { return tutorialGame.opening.name }
    if firstGame || basicRun { return openingNameForPath(index, run.played)?.name ?? "Any Opening" }
    if round?.free == true { return openingNameForPath(index, run.played)?.name ?? "Freeform" }
    return openingName(tree, openingId)
  }
  /// The header's line over its name: the opening's family, when the name is deeper than it.
  public var headerFamily: String? { familyAbove(index, headerName) }
  public var momentHere: Bool {
    prefs.moments && live && myTurn && pending == nil && prepNow.isEmpty && baseline?.fen == run.fen && baseline?.isMomentFor(run.color) == true
  }

  /// On your prep in a Play run: your line's moves are still to play.
  public var inPrep: Bool { round != nil && live && intro == .done && fill == nil && prepLabel(session) == .on }

  /// Next run was tapped: the round ends on the board, and the next one follows without the end screen.
  public var advancing = false

  /// Next run: past your prep in a Play run. In the tutorial, once its game asks you to end it, or in its last game.
  public var nextRunShown: Bool {
    guard round != nil, live, intro == .done, fill == nil, session.prepStatus != .on else { return false }
    if let tutorialGame { return tutorialGame.number >= TUTORIAL_GAMES || (endCued && tutorialGame.tips.contains(.nextRun)) }
    return true
  }

  /// The opening's own rating, as this run moved it.
  public var ratingMoment: RatingMoment? {
    #if DEBUG
      // `RATING_MOMENT=240,262` plays that change, for checking the playback.
      if let raw = ProcessInfo.processInfo.environment["RATING_MOMENT"]?.split(separator: ",").compactMap({ Double($0) }), raw.count == 2 {
        return RatingMoment(name: openingName(tree, openingId), before: raw[0], after: raw[1])
      }
    #endif
    guard let r = ratings.byKey[openingId], JSRound(r.after - r.before) != 0, nodeById(tree, openingId).depth > 0 else { return nil }
    return RatingMoment(name: openingName(tree, openingId), before: r.before, after: r.after)
  }

  /// A word over the board for a moment: leaving your prep, or a find.
  public struct Callout: Equatable {
    public var text: String
    public var good: Bool
    public var id: Int
  }
  public private(set) var callout: Callout?
  /// The last callout for leaving your prep.
  private var prepCallout: Callout?
  private var calloutCount = 0
  /// How long a callout stays.
  public static let calloutMs = 1.5

  /// The callout on the board: a tip about leaving your prep keeps its callout up.
  public var shownCallout: Callout? { callout ?? (tip == .playOn ? prepCallout : nil) }

  private func show(callout text: String, good: Bool, prep: Bool = false) {
    calloutCount += 1
    let shown = Callout(text: text, good: good, id: calloutCount)
    callout = shown
    services.emit(.callout(text, good: good))
    if prep { prepCallout = shown }
    later(Self.calloutMs) { model in
      if model.callout == shown { model.callout = nil }
    }
  }

  /// Your prep just ended, finished or missed: a Play run says so over the board.
  private func noteLeft(_ was: PrepLabel?) {
    guard round != nil, was == .on, session.prepStatus != .on else { return }
    show(callout: session.prepStatus == .off ? "Off prep" : "Prep complete", good: session.prepStatus != .off, prep: true)
  }

  /// The board as shown: your move stands while it is judged, a blunder stays until Continue.
  public var shownFen: String {
    if held && !introPath.isEmpty { return walkSan(introPath).fens[min(introPly, introPath.count)] }
    if let flash { return flash.move.after }
    if let pending { return pending.after }
    if case .blunder(let played, _, _, _, _) = session.ending, phase == .blunder { return applySan(run.fen, played)?.after ?? run.fen }
    return run.fen
  }

  /// The blunder and the threat that made it one.
  public var blunder: (move: LegalMove, threat: LegalMove?)? {
    guard phase == .blunder, case .blunder(let played, _, _, let reply, _) = session.ending, let move = applySan(run.fen, played) else { return nil }
    return (move, reply.flatMap { applyUci(move.after, $0) })
  }

  /// A Middlegame run was announced while its handoff was built, so it goes straight to the board,
  /// as do the first game and the tutorial's first. Later tutorial games are announced like any round.
  /// `dealt`: its card was drawn from the deck and is already on the board, so no announcement.
  public func start(dealt: Bool = false) {
    let straightIn = dealt || handoff != nil || firstGame || (tutorialGame.map { $0.number <= 1 } ?? false)
    if straightIn { toBoard() } else { later(round != nil ? services.dealSeconds : Self.announceMs) { $0.toBoard() } }
  }

  /// The announcement gives way to the board: the way in plays out, or the round begins.
  public func toBoard() {
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
    if replaying {
      // The round was under way already: your turn starts again, with the time spent watching off the clock.
      replaying = false
      introPly = 0
      intro = .done
      pulseEdge()
      turnStartedAt = now
      return
    }
    if handoff != nil && structureOf(run.fen) != nil {
      intro = .plan
      return
    }
    intro = .done
    pulseEdge()
    begin()
  }

  /// The plan card's Play: your clock starts.
  public func playFromHandoff() {
    guard intro == .plan else { return }
    intro = .done
    pulseEdge()
    begin()
  }

  /// The board's edge pulses once the replay hands you the move.
  public private(set) var pulse = false

  private func pulseEdge() {
    pulse = true
    later(Self.pulseMs) { $0.pulse = false }
  }

  /// A tap skips the rest of the replay.
  public func skipIntro() {
    guard intro == .replay else { return }
    replayDone()
  }

  private func begin() {
    spanHeld = span
    advance()
  }

  public func stop() {
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
  private var replyEngine: ChessEngine { services.engine("reply") }
  /// The reply searched ahead, for the position after your move.
  private var reply: (fen: String, search: Task<EngineSnapshot, Never>)?

  /// Start searching the opponent's reply to your move straight away.
  private func searchReply(after fen: String) {
    reply?.search.cancel()
    let level = opponentLevel
    let engine = replyEngine
    // Its own counted task, so a headless game waits for it to finish.
    let search = Task { await engine.analyse(fen, EngineLimits(depth: level.depth, multiPv: level.multiPv)) }
    services.spawn { _ = await search.value }
    reply = (fen, search)
  }

  private func opponent() {
    thinking = true
    spawn { [weak self] in
      guard let self else { return }
      await self.services.sleep(Self.replyMs)
      guard !Task.isCancelled, self.live, !self.myTurn else { return }
      if let game = self.tutorialGame {
        if let san = tutorialReply(game, played: self.run.played, line: self.tutorialLine, self.index) {
          self.thinking = false
          self.apply(engineMove(self.session, san))
          return
        }
      } else if let step = bookTurn(self.session, self.index, self.picker) {
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
        snap = await self.replyEngine.analyse(fen, EngineLimits(depth: level.depth, multiPv: level.multiPv))
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
    turnStartedAt = now
    // Adding moves: the player picks the next one, nothing is weighed.
    if fill != nil {
      showTip()
      return
    }
    if prepNow.isEmpty { update(prepRanOut(session, index)) }
    update(closeBook(session, index))
    askAtHole()
    if let game = tutorialGame {
      if !tutorialGrown && session.state.misses.isEmpty && tutorialGrowsHere(game, played: run.played, line: tutorialLine),
        let rep = store.state.playbookList.first(where: { $0.color == game.color }) {
        tutorialGrown = true
        tutorialLine = run.played
        fill = Fill(gap: tutorialGap(rep, run.played), size: game.growth)
        pulseEdge()
      } else if tutorialEndCue(game, played: run.played, line: tutorialLine, scored: tutorialScored, index) {
        endCued = true
      }
    }
    showTip()
    if fill != nil || endCued { return }
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
    }
  }

  /// You played a move on the board. With the Undefended flash on, a move
  /// that leaves a piece loose is held a moment first, to take back.
  public func play(_ move: LegalMove) {
    guard live, !held, myTurn, pending == nil, flash == nil, !endCued else { return }
    if let expected, move.san != expected { return }
    if tip != nil { dismissTip() }
    if fill != nil {
      if fillChoices.contains(where: { $0.san == move.san }) { addMove(move.san) }
      return
    }
    // Your time stops when you move, not when a held move lands.
    let seconds = now - turnStartedAt
    if prefs.undefendedFlash {
      let loose = newlyLoose(run.fen, move.after, run.color, from: move.from, to: move.to)
      if !loose.isEmpty {
        services.emit(.buzz(12))
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
  public func takeBack() { flash = nil }

  private func commit(_ move: LegalMove, seconds: Double) {
    guard live, !held, myTurn, pending == nil else { return }
    miss = nil
    missedBest = nil
    holeGap = nil
    let now = Env.now()
    if prepNow.contains(move.san) {
      apply(playPrepared(session, ctx, move, seconds, now))
      return
    }
    pending = move
    // Past your line, a tutorial counts the moves the engine scores rather than lets pass as common.
    let pastLine = prepNow.isEmpty
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
      let step = judgedMove(self.session, self.ctx, judged, seconds, now)
      if self.tutorialGame != nil && pastLine && step.session.bookMoves == self.session.bookMoves { self.tutorialScored += 1 }
      self.apply(step)
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
    // A round set to grow here grows whatever the line's need.
    if found.yes || found.gap.line == round?.grow?.line { startFill(found.gap) } else { holeGap = found.gap }
  }

  /// The answers on offer while adding moves, the same as Growth's.
  public var fillChoices: [Reply] { fill == nil ? [] : ranked }

  /// Add moves here, at the engine's word or the player's.
  public func growHere() {
    guard let gap = holeGap, live, myTurn, pending == nil else { return }
    startFill(gap)
  }

  private func startFill(_ gap: Gap) {
    holeGap = nil
    fill = Fill(gap: gap, size: store.state.settings.movesPerFill)
    pulseEdge()
    store.update { $0.logEvent(AppEvent(kind: "inline-grow", via: .play, color: gap.color, line: gap.line.joined(separator: " "))) }
  }

  /// A move picked while adding: saved to the Playbook, then played.
  public func addMove(_ san: String) {
    guard var current = fill, live, myTurn, pending == nil else { return }
    if tip != nil { dismissTip() }
    let rid = current.gap.playbookId
    let line = run.played + [san]
    let offered = fillChoices.map(\.san)
    let move = applySan(run.fen, san)
    // Undo removes from the first move this line added.
    let rep = store.state.playbooks[rid]
    let fresh = (1...line.count).first { k in rep.flatMap { nodeAtLine($0, Array(line.prefix(k))) } == nil } ?? line.count
    current.steps.append((session, Array(line.prefix(fresh))))
    filledRep = rid
    if tutorialGame != nil { tutorialLine = line }
    store.update { state in
      state.addGrowthLine(rid, line, index)
      state.logEvent(AppEvent(
        kind: "growth-pick", via: .play, color: run.color, line: run.played.joined(separator: " "), picked: san, offered: offered))
    }
    services.emit(.buzz(10))
    let ends = tutorialGame != nil ? current.added >= current.size : fillEnds(index, line, added: current.added, size: current.size)
    fill = ends ? nil : current
    if fill == nil {
      holeGap = nil
      tutorialJustGrown = tutorialGame != nil
    }
    justAdded = fill == nil ? nil : move.map { ($0.from, $0.to) }
    apply(playAdded(session, san))
  }

  /// The opponent's reply while adding moves: the gap's own move on the way
  /// to it, the tutorial's set answer to move one, or the book's most played.
  private func fillReply() {
    thinking = true
    later(Self.replyMs) { model in
      model.thinking = false
      guard model.live, !model.myTurn, model.fill != nil else { return }
      model.justAdded = nil
      let played = model.run.played
      let line = model.fill?.gap.line ?? []
      let toGap = line.count > played.count && Array(line.prefix(played.count)) == played ? line[played.count] : nil
      let scripted = model.tutorialGame.flatMap { tutorialReply($0, played: played, line: model.tutorialLine, model.index) }
      guard let san = toGap ?? scripted ?? popularReplies(model.index, model.run.fen, GAP_SHARE).first?.san else {
        model.fill = nil
        model.advance()
        return
      }
      model.apply(playFillReply(model.session, san))
    }
  }

  /// Undo while adding: the last move added comes out of the Playbook and off the board.
  public func undoAdded() {
    guard var current = fill, !current.steps.isEmpty else { return }
    let last = current.steps.removeLast()
    let rid = current.gap.playbookId
    stop()
    thinking = false
    store.update { state in
      if let rep = state.playbooks[rid], let node = nodeAtLine(rep, last.remove) { _ = state.removeNode(rid, node.id, via: .play) }
    }
    session = last.session
    justAdded = nil
    fill = current
    if let tutorialGame { tutorialLine = run.played.count >= tutorialGame.opening.sans.count ? run.played : tutorialGame.opening.sans }
  }

  /* ── the tutorial's tips ── */

  /// The forced move on your turn in a tutorial game: the only one the board takes, shown with an arrow.
  public var expected: String? {
    guard let game = tutorialGame, live, !held, myTurn, fill == nil, !endCued else { return nil }
    return tutorialExpected(game, played: run.played, line: tutorialLine, index)
  }

  /// The tutorial's arrow: the move it insists on, or your line's next move in its free last game.
  public var shownMove: String? {
    guard let game = tutorialGame, live, !held, myTurn, fill == nil, !endCued else { return nil }
    return tutorialShown(game, played: run.played, line: tutorialLine, index)
  }

  /// The tip for where the tutorial game stands, if one is still to show there.
  private func showTip() {
    guard let game = tutorialGame, tip == nil, live else { return }
    let played = run.played
    var now = Set<TutorialMoment>()
    if endCued { now.insert(.endCue) }
    if fill != nil && myTurn { now.insert(.growthOpen) }
    if tutorialJustGrown && fill == nil {
      now.insert(.growthEnded)
      tutorialJustGrown = false
    }
    if tutorialScored > 0 { now.insert(.scored) }
    if prepCallout != nil { now.insert(.leftPrep) }
    if fill == nil && played.count >= tutorialLine.count {
      now.insert(ownPast(game.color, played, tutorialLine) == 0 ? .pastLine : .pastCommon)
    }
    if played.count < tutorialLine.count {
      let own = played.indices.filter { ($0 % 2 == 0) == (game.color == .w) }.count
      now.insert(own == 0 ? .start : .moved)
    }
    guard let found = tutorialTip(store.state.settings.tips, now) else { return }
    tip = found
    store.update { $0.settings.tips.removeAll { $0 == found } }
  }

  /// A finished tutorial game holds its board until you leave, and a tap anywhere moves it on.
  public var tapsLeave: Bool { tutorialGame != nil && finish != nil }

  /// A tap anywhere on a finished tutorial game: the blunder tip is put away
  /// (the tip on the X follows), else true, and the game is left for Home.
  public func tapFinished() -> Bool {
    guard tapsLeave else { return false }
    if tip == .blunder {
      dismissTip()
      return false
    }
    return true
  }

  /// A tap on the tip, or your next move: some tips lead to the next.
  public func dismissTip() {
    guard let current = tip else { return }
    if current == .blunder, tutorialGame != nil, finish != nil {
      tip = .goHome
      return
    }
    if let next = current.next, store.state.settings.tips.contains(next) {
      tip = next
      store.update { $0.settings.tips.removeAll { $0 == next } }
    } else {
      tip = nil
    }
  }

  /// The goal card stays away in the tutorial's games.
  public var tipsInPlay: Bool { tutorialGame != nil }

  /// Done: no more moves added, and the game goes on from here.
  public func doneAdding() {
    guard fill != nil else { return }
    fill = nil
    tutorialJustGrown = tutorialGame != nil
    justAdded = nil
    advance()
  }

  /// The app went to the background or the screen locked: the clock stops.
  public func appLeft() {
    if awaySince == nil { awaySince = now }
  }

  /// Back on screen: the clock goes on from where it stopped.
  public func appReturned() {
    guard let away = awaySince else { return }
    awaySince = nil
    turnStartedAt += now - away
  }

  /// You ended the round.
  public func endRound() {
    guard finish == nil else { return }
    stop()
    pending = nil
    flash = nil
    apply(endRun(session))
  }

  /// Past the blunder, on to the end screen.
  public func continueToEnd() { phase = .over }

  /* ── the controller's steps ── */

  private func update(_ next: RunSession) {
    let was = prepLabel(session)
    session = next
    noteLeft(was)
    if session.prepStatus != .off { spanHeld = span }
  }

  private func apply(_ step: Step) {
    if step.session.prepStatus == .off && session.prepStatus != .off { spanHeld = span }
    let was = prepLabel(session)
    session = step.session
    noteLeft(was)
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
        services.emit(.buzz(pattern))
      case .pop(let p):
        show(pop: p)
      case .note(let n):
        // A word on what the move earned: a callout, like a find.
        if let n { show(callout: n.text, good: n.tone == "good") }
      case .miss(let m):
        show(miss: m)
      case .moment(let found):
        if found { show(callout: "Found it", good: true) }
        if found { services.emit(.success) }
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
    if let game = tutorialGame {
      var blundered = false
      if case .blunder = f.how { blundered = true }
      var ended = false
      if case .ended = f.how { ended = true }
      // Ended by hand before its end, the game is played again.
      let counted = endCued || game.number >= 4 || !ended
      // Ended on its own board, the game points at its X, after the blunder tip on a blunder.
      tip = blundered ? .blunder : ended ? nil : .goHome
      store.update { $0.settings.finishTutorialGame(counted: counted) }
    }
    before = handoff != nil ? store.state.middlegame : store.state.runRecord
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
        state.endRunEarly(tree, line)
      } else {
        state.recordRunEnd(tree, line, f.ended.moves, points)
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
    let mode: GameMode = handoff != nil ? .middlegame : round != nil ? .play : .run
    return GameRecord(
      id: run.id, mode: mode, at: Env.now(), color: run.color, picked: selection,
      opening: run.openingId, moves: run.played, opened: run.opened, result: outcome.result, termination: outcome.termination)
  }

  /// What floats over the board goes, and the blunder or the end screen comes up.
  private func settle(_ f: Finish) {
    pop = nil
    miss = nil
    flash = nil
    thinking = false
    if case .blunder = f.how {
      services.emit(.buzz(22))
      phase = .blunder
    } else {
      phase = .over
    }
  }

  /* ── what floats over the board ── */

  private func show(pop p: Pop) {
    pop = p
    popCount += 1
    services.emit(.pop(p))
    later(Self.scoreMs) { model in
      if model.pop == p { model.pop = nil }
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
    services.emit(.miss(m))
    later(Self.missMs) { model in
      guard model.miss == m else { return }
      model.miss = nil
      model.advance()
    }
  }

  /// A touch anywhere clears a miss sooner. The missed moment's squares stay.
  public func clearOverlays() {
    guard miss != nil else { return }
    miss = nil
    advance()
  }

  private func later(_ seconds: Double, _ then: @escaping @MainActor (RunModel) -> Void) {
    let clock = services.clock
    spawn { [weak self] in
      await clock.sleep(seconds)
      if let self, !Task.isCancelled { then(self) }
    }
  }

  private func spawn(_ work: @escaping @MainActor () async -> Void) {
    tasks.removeAll { $0.isCancelled }
    tasks.append(services.spawn(work))
  }
}

/// Each opening's rating over a run: where it stood before its first move, and after its last.
/// `changes` lists them in the order first moved.
/// A rating a round moved: where it stood and where it stands.
public struct RatingMoment: Equatable, Sendable {
  public var name: String
  public var before: Double
  public var after: Double
  public init(name: String, before: Double, after: Double) {
    self.name = name
    self.before = before
    self.after = after
  }
}

public struct OrderedRatings {
  public struct Change {
    public var id: String
    public var before: Double
    public var after: Double
    public var delta: Double { after - before }
  }

  public private(set) var changes: [Change] = []

  public init() {}

  public var byKey: [String: (before: Double, after: Double)] {
    Dictionary(changes.map { ($0.id, ($0.before, $0.after)) }, uniquingKeysWith: { a, _ in a })
  }

  public mutating func track(_ moves: [RatingMove]) {
    for move in moves {
      if let i = changes.firstIndex(where: { $0.id == move.id }) {
        changes[i].after = move.after
      } else {
        changes.append(Change(id: move.id, before: move.before, after: move.after))
      }
    }
  }
}

extension RunModel: HoleAnswers {
  public var atHole: Bool { fill != nil && live && myTurn }
  public var holeFen: String { run.fen }
  public var holePath: [String] { run.played }
  public var answerColor: ChessCore.Color { run.color }
  public var answerTree: Playbook? { fill.flatMap { store.state.playbooks[$0.gap.playbookId] } }
  public var nudgePrefs: NudgePrefs {
    let prefs = store.state.settings.growth
    return NudgePrefs(priority: prefs.nudgePriority, pawns: prefs.nudgePawns)
  }
  /// A fill answers gaps, so it offers what a gap's Growth sitting would.
  public var minShare: Double { GAP_SHARE }
  /// Tutorial growth that offers one answer: the script's, else the book's most played.
  public var onlyAnswer: String? {
    guard let game = tutorialGame, game.oneOption, fill != nil else { return nil }
    return tutorialScripted(game, run.played) ?? bookTop(index, run.played)
  }
}
