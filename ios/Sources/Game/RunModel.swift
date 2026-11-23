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
  public private(set) var finish: Finish?
  /// The end screen has opened once: its verdict has played, and stays at rest after.
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
  /// The Prep complete pawns, held while growth is due here: one move added pays them.
  public private(set) var heldPrepPawn: PawnAward?
  /// The pawns in the prep's pot: one for each prepared move found, paid when the prep completes.
  public private(set) var pot = 0
  /// The square of the last prepared move found, whose pawn went into the pot.
  private var lastPotSquare: String?
  /// The pot lost to a miss, or to growth left with nothing added: how many it held. `id` restarts its drain.
  public private(set) var potDrain: (count: Int, id: Int)?
  /// The run has reached its one hole and asked about it.
  private var holeAsked = false
  /// A new player's first game: nothing saved, adding moves from move one, with tips.
  public private(set) var firstGame = false
  /// A Play run filling a Black basic from move one.
  public private(set) var basicRun = false
  /// The tip on screen.
  public private(set) var tip: GameTip?
  /// Your moves played this run.
  private var ownMoves = 0
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
      fill = Fill(gap: first, size: MOVES_PER_FILL)
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
    fill = Fill(gap: firstMoveGap(rep, index), size: MOVES_PER_FILL)
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

  /// The distance bar in the header, once your prep is behind you: your moves toward the next
  /// marker and what it pays. Nil while the prep's bar shows: in your prep, and past it until
  /// your first move there, so the prep's pot can pay out or drain. Nil again once markers stop:
  /// under endgame rules, or past the run's last marker.
  public var marker: (moves: Int, pays: Int)? {
    guard intro == .done, countsTowardMarker(pastPrep: session.pastPrep, endgame: session.state.extras.endgame) else { return nil }
    if session.pastPrep == 0 && !session.middlegame && prepLabel(session) != nil { return nil }
    return nextMarker(session.pastPrep, middlegame: session.middlegame)
  }

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
    guard let book = headerBookName else { return round?.free == true && !firstGame && !basicRun ? "Freeform" : "Any Opening" }
    guard store.state.settings.openingNames == .book else { return openingFamily(index, book) ?? familyName(index, book) }
    if firstGame || basicRun || round?.free == true { return book }
    return openingName(tree, openingId)
  }
  /// The header's line over its name, with book names: the opening's family, when the name is deeper than it.
  public var headerFamily: String? {
    guard store.state.settings.openingNames == .book, let book = headerBookName, let family = familyAbove(index, book) else { return nil }
    return family == headerName ? nil : family
  }
  /// The book's full name for the run's opening; nil for none.
  private var headerBookName: String? {
    if firstGame || basicRun || round?.free == true { return openingNameForPath(index, run.played)?.name }
    let node = nodeById(tree, openingId)
    return node.depth > 0 ? node.name : nil
  }
  public var momentHere: Bool {
    prefs.moments && live && myTurn && pending == nil && prepNow.isEmpty && baseline?.fen == run.fen && baseline?.isMomentFor(run.color) == true
  }

  /// On your prep in a Play run: your line's moves are still to play.
  public var inPrep: Bool { round != nil && live && intro == .done && fill == nil && prepLabel(session) == .on }

  /// Next run was tapped: the round ends on the board, and the next one follows without the end screen.
  public var advancing = false

  /// Next run: past your prep in a Play run.
  public var nextRunShown: Bool {
    round != nil && live && intro == .done && fill == nil && session.prepStatus != .on
  }

  /// A word over the board for a moment: leaving your prep, or a find.
  public struct Callout: Equatable {
    public var text: String
    public var good: Bool
    public var id: Int
    /// A chance you missed, in its own color.
    public var missed = false
  }
  public private(set) var callout: Callout?
  private var calloutCount = 0
  /// How long a callout stays.
  public static let calloutMs = 1.5

  /// The callout on the board.
  public var shownCallout: Callout? { callout }

  private func show(callout text: String, good: Bool, missed: Bool = false) {
    log("callout") { $0.text = text }
    calloutCount += 1
    let shown = Callout(text: text, good: good, id: calloutCount, missed: missed)
    callout = shown
    services.emit(.callout(text, good: good))
    later(Self.calloutMs) { model in
      if model.callout == shown { model.callout = nil }
    }
  }

  /// Your prep just missed: a Play run says Off prep under the board. A finished prep says nothing
  /// there: its pawns fly to the header with their own Prep complete.
  private func noteLeft(_ was: PrepLabel?) {
    guard round != nil, was == .on, session.prepStatus == .off else { return }
    show(callout: "Off prep", good: false)
  }

  /// The board as shown: your move stands while it is judged, a blunder stays on it.
  public var shownFen: String {
    if held && !introPath.isEmpty { return walkSan(introPath).fens[min(introPly, introPath.count)] }
    if let flash { return flash.move.after }
    if let pending { return pending.after }
    if case .blunder(let played, _, _, _, _) = session.ending, phase == .blunder { return applySan(run.fen, played)?.after ?? run.fen }
    return run.fen
  }

  /// The blunder and the threat that made it one.
  public var blunder: (move: LegalMove, threat: LegalMove?)? {
    guard phase == .blunder, case .blunder(let played, _, _, let line, _) = session.ending, let move = applySan(run.fen, played) else { return nil }
    return (move, line.first.flatMap { applyUci(move.after, $0) })
  }

  /// A Middlegame run was announced while its handoff was built, so it goes straight to the board,
  /// as does the first game.
  /// `dealt`: its card was drawn from the deck and is already on the board, so no announcement.
  public func start(dealt: Bool = false) {
    let straightIn = dealt || handoff != nil || firstGame
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
    log("game-start") {
      $0.source = self.handoff != nil ? "middlegame" : self.round.map { $0.free ? "freeform" : "drill" } ?? "run"
      $0.line = self.run.played.joined(separator: " ")
      $0.picked = "\(self.selection.color) \(self.selection.opening)"
      $0.text = self.headerName
      $0.fen = self.run.fen
    }
    if round != nil && prepLabel(session) == .on { offer(.flashCards) }
    if round?.free == true { offer(.freeformGame) }
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
      if let step = bookTurn(self.session, self.index, self.picker) {
        self.thinking = false
        self.log("reply") { $0.san = step.session.state.run.played.last; $0.source = "book"; $0.fen = self.run.fen }
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
        self.log("reply") { $0.san = san; $0.source = "engine"; $0.fen = fen; $0.text = "level \(level.rating)" }
        self.apply(engineMove(self.session, san))
      }
    }
  }

  /// Your turn begins: what the screen settles before you move.
  private func beginTurn() {
    turnStartedAt = now
    // Adding moves: the player picks the next one, nothing is weighed.
    if fill != nil {
      offer(.growth)
      offerToneTip()
      return
    }
    if prepNow.isEmpty {
      let ran = prepRanOut(session, index)
      update(ran.session)
      perform(ran.effects)
    }
    update(closeBook(session, index))
    askAtHole()
    if fill != nil {
      // Growth is due: the prep pawn waits for a move added.
      offer(.growth)
      if heldPrepPawn != nil { offer(.growthPawn) }
      offerToneTip()
      return
    }
    payHeldPrepPawn(fresh: true)
    if inPrep && ownMoves > 0 { offer(.prepBar) }
    if nextRunShown { offer(.nextRun) }
    if prepNow.isEmpty && store.state.ownsALens { offer(.lens) }
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
      self.logLook(base)
      self.update(sawEval(self.session, base.cp))
      let had = self.session.state.extras.mission != nil
      if self.live && self.myTurn { self.update(missionFrom(self.session, self.prefs, base.cp)) }
      if !had, let mission = self.session.state.extras.mission { self.log("mission") { $0.text = mission.kind.rawValue; $0.before = base.cp } }
      if self.prefs.missions && self.session.state.extras.mission != nil { self.offer(.mission) }
    }
  }

  /// You played a move on the board. With the Undefended flash on, a move
  /// that leaves a piece loose is held a moment first, to take back.
  public func play(_ move: LegalMove) {
    guard live, !held, myTurn, pending == nil, flash == nil else { return }
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
    ownMoves += 1
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
      if base == nil {
        base = await Engine.baseline(self.engine, fen, moments: moments)
        if let base { self.logLook(base) }
      }
      guard let base else {
        self.pending = nil
        return
      }
      let judged = await judge(self.engine, base, san: move.san, uci: move.uci, color: color, moments: moments, reached: reached)
      self.pending = nil
      // Ended while the judge was out: the move never counted.
      guard !Task.isCancelled, self.live, self.run.fen == fen else { return }
      self.log("move") {
        $0.san = move.san
        $0.fen = fen
        $0.before = judged.before
        $0.after = judged.after
        $0.lost = judged.lost
        $0.ok = judged.ok
        $0.best = judged.best
        $0.moment = judged.moment
        $0.found = judged.found
        $0.seconds = seconds
        if judged.missedMate { $0.text = "missed mate" }
        $0.yours = judged.yours
        $0.top = judged.top
        $0.depth = judged.depth
      }
      self.store.update { $0.judgedMove(lost: judged.lost) }
      let step = judgedMove(self.session, self.ctx, judged, seconds, now)
      self.apply(step)
    }
  }

  /* ── adding moves mid-run ── */

  /// At the run's one hole, ask the engine whether the line needs a new move now.
  private func askAtHole() {
    // A round started at the gap it grows: growth opens at once.
    if !holeAsked, let grow = round?.grow, !grow.hole.path.isEmpty, run.played == grow.line, myTurn {
      holeAsked = true
      startFill(grow)
      return
    }
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
    fill = Fill(gap: gap, size: MOVES_PER_FILL)
    pulseEdge()
    // Adding moves takes the screen: whatever tip was up gives way to growth's.
    tip = nil
    offer(.growth)
    // Green and red need the engine's word: their tip waits for the evals.
    services.growthEngine.onEvals = { [weak self] in self?.offerToneTip() }
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
    // The held prep pawns fly out of the pot.
    payHeldPrepPawn()
    store.update { state in
      state.addGrowthLine(rid, line, index)
      state.logEvent(AppEvent(
        kind: "growth-pick", via: .play, color: run.color, line: run.played.joined(separator: " "), picked: san, offered: offered))
    }
    services.emit(.buzz(10))
    let ends = fillEnds(index, line, added: current.added, size: current.size)
    fill = ends ? nil : current
    if fill == nil { holeGap = nil }
    justAdded = fill == nil ? nil : move.map { ($0.from, $0.to) }
    apply(playAdded(session, san))
  }

  /// The opponent's reply while adding moves: the gap's own move on the way
  /// to it, or the book's most played.
  private func fillReply() {
    thinking = true
    later(Self.replyMs) { model in
      model.thinking = false
      guard model.live, !model.myTurn, model.fill != nil else { return }
      model.justAdded = nil
      let played = model.run.played
      let line = model.fill?.gap.line ?? []
      let toGap = line.count > played.count && Array(line.prefix(played.count)) == played ? line[played.count] : nil
      guard let san = toGap ?? popularReplies(model.index, model.run.fen, GAP_SHARE).first?.san else {
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
  }

  /* ── tips ── */

  /// A tip whose trigger has come: it shows unless another is up or it has shown before.
  private func offer(_ next: GameTip) {
    guard tip == nil, !store.state.settings.seen(next) else { return }
    tip = next
    store.update { $0.sawTip(next) }
  }

  /// Growth's green or red, the first time each is drawn.
  public func offerToneTip() {
    guard atHole, let next = toneTip(toned.map(\.tone), seen: store.state.settings.seen) else { return }
    offer(next)
  }

  /// Pawns paid: what they are for, and in Play, once there are enough to spend, the way to the Pawn Shop.
  private func offerPawnTips() {
    offer(.pawns)
    if round != nil && store.state.pawns >= END_SESSION_TIP_PAWNS { offer(.endSession) }
  }

  /// A tap on the tip, or your next move.
  public func dismissTip() { tip = nil }

  /// Done: no more moves added, and the game goes on from here.
  public func doneAdding() {
    guard fill != nil else { return }
    dropHeldPrepPawn()
    fill = nil
    justAdded = nil
    advance()
  }

  /// The app went to the background or the screen locked: the clock stops.
  public func appLeft() {
    if awaySince == nil { log("app-left") }
    if awaySince == nil { awaySince = now }
  }

  /// Back on screen: the clock goes on from where it stopped.
  public func appReturned() {
    guard let away = awaySince else { return }
    log("app-returned") { $0.seconds = self.now - away }
    awaySince = nil
    turnStartedAt += now - away
  }

  /// You ended the round.
  public func endRound() {
    guard finish == nil else { return }
    log("end-round")
    stop()
    pending = nil
    flash = nil
    apply(endRun(session))
  }

  /// Past the blunder, on to the end screen.
  public func continueToEnd() {
    phase = .over
  }

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
    perform(step.effects)
    advance()
  }

  /* ── the log ── */

  /// One more event in the log, from this game.
  private func log(_ kind: String, _ fill: (inout AppEvent) -> Void = { _ in }) {
    var event = AppEvent(kind: kind, color: run.color)
    event.game = run.id
    fill(&event)
    store.log(event)
  }

  /// The engine's first look at a position: its eval, its move, and whether it is a moment.
  private func logLook(_ base: Baseline) {
    log("eval") {
      $0.fen = base.fen
      $0.before = base.cp
      $0.best = base.best
      $0.moment = base.isMomentFor(self.run.color)
      $0.text = base.second.map { "second \($0.uci) \($0.cp)" }
    }
  }

  /// The controller's effects, in order.
  private func perform(_ effects: [Effect]) {
    for effect in effects {
      switch effect {
      case .answer(let result):
        store.update { $0.recordMove(tree, result) }
      case .answered(let rid, let fen, let san, let grade):
        log("prep-answer") { $0.san = san; $0.fen = fen; $0.text = "\(grade)"; $0.playbookId = rid }
        store.update { $0.answered(rid, fen, san, grade) }
      case .missed(let rid, let fen, let played, let expected):
        log("prep-miss") { $0.san = played; $0.best = expected; $0.fen = fen; $0.playbookId = rid }
        store.update { $0.missed(rid, fen, played, expected) }
      case .buzz(let pattern):
        services.emit(.buzz(pattern))
      case .pop(let p):
        show(pop: p)
        // The first ✓ on a common move past your prep says what it means.
        if p.book { offer(.prepDone) }
      case .note(let n):
        // A word on what the move earned: a callout, like a find.
        if let n { show(callout: n.text, good: n.tone == "good", missed: n.tone == "missed") }
      case .miss(let m):
        show(miss: m)
        drainPot()
        offer(.missedMove)
      case .moment(let found):
        if found { show(callout: "Found it", good: true) }
        if found { services.emit(.success) }
        pulse(found: found)
      case .missedBest(let move):
        missedBest = move
      case .potPawn(let square):
        pot += 1
        lastPotSquare = square
        store.dropInPot(square)
      case .pawns(let award) where award.event == .prepComplete:
        // Held until this turn knows whether growth is due here.
        heldPrepPawn = award
      case .pawns(let award):
        pay(award)
        if award.event == .distance { offer(.distancePawns) }
        offerPawnTips()
      case .finish(let f):
        finished(f)
      }
    }
  }

  /* ── pawns ── */

  /// Pawns earned go straight onto the balance, and fly to the counter.
  private func pay(_ award: PawnAward) {
    store.pay(award)
  }

  /// The held prep pawns, paid out of the pot: a move was added, or growth wasn't due after all.
  /// Paid the turn the prep ran out (`fresh`), the last prepared move's pawn goes straight to the
  /// counter and the pot pays the rest; held for growth, every pawn is in the pot and it pays them all.
  private func payHeldPrepPawn(fresh: Bool = false) {
    guard let award = heldPrepPawn else { return }
    heldPrepPawn = nil
    pot = 0
    if fresh, let square = lastPotSquare { store.payPot(award, lastSquare: square) } else { pay(award) }
    offerPawnTips()
  }

  /// The held prep pawns, lost: growth was left with nothing added. The pot drains.
  private func dropHeldPrepPawn() {
    guard let award = heldPrepPawn else { return }
    heldPrepPawn = nil
    session.state.extras.pawns -= award.count
    drainPot()
    log("pawns-withheld") { $0.source = award.event.rawValue; $0.count = award.count }
  }

  /// The pot is lost: what it held drains away, and nothing reaches the counter.
  private func drainPot() {
    guard pot > 0 else { return }
    potDrain = (pot, (potDrain?.id ?? 0) + 1)
    pot = 0
  }

  private func finished(_ f: Finish) {
    dropHeldPrepPawn()
    stop()
    finish = f
    log("game-end") { $0.text = "\(f.how)"; $0.count = f.ended.run.played.count; $0.line = f.ended.run.played.joined(separator: " ") }
    tip = nil
    // Next run goes straight on: no game is left on the board to look back on.
    if case .blunder = f.how { offer(.blunder) } else if handoff == nil && !advancing { offer(.analysis) }
    before = handoff != nil ? store.state.middlegame : store.state.runRecord
    let line = f.ended.run.played
    let counted = f.ended.moves
    // The streak's day comes from a game whose prep was completed; Middlegame asks no prep.
    if handoff != nil || session.prepStatus == .complete { store.finishedGame() }
    // An endgame result that slipped away is kept for Endgame mode, from the position before the move.
    let given = endgameGivenAway(f.how, fen: f.ended.run.fen, name: openingName(tree, f.ended.run.openingId), at: Env.now())
    // Built before the update: reading the store inside its own update is an exclusivity crash.
    let record = game(f)
    store.update { $0.recordGame(record) }
    if let handoff {
      // Counted against the openings your own line went through. No prep was asked, so no form or card moves.
      let yours = Array(handoff.line.prefix(handoff.prep))
      store.update { state in
        if case .ended = f.how { state.endMiddlegameEarly(tree, yours) } else { state.endMiddlegame(tree, yours, counted) }
        if let given { state.endgames.save(given) }
      }
      settle(f)
      return
    }
    store.update { state in
      if case .ended = f.how {
        state.endRunEarly(tree, line)
      } else {
        state.recordRunEnd(tree, line, counted)
      }
      state.endRound(tree, runRound(f, tree, at: Env.now()))
      if let given { state.endgames.save(given) }
    }
    settle(f)
  }

  /// The run as a game for the history, the move that lost included.
  private func game(_ f: Finish) -> GameRecord {
    let run = f.ended.run
    var moves = run.played
    if case .blunder(let played, _, _, _, _) = f.how { moves.append(played) }
    let outcome = runOutcome(f.how, color: run.color)
    let mode: GameMode = handoff != nil ? .middlegame : round != nil ? .play : .run
    return GameRecord(
      id: run.id, mode: mode, at: Env.now(), color: run.color, picked: selection,
      opening: run.openingId, moves: moves, opened: run.opened, result: outcome.result, termination: outcome.termination)
  }

  /// What floats over the board goes, and the blunder or the end screen comes up.
  private func settle(_ f: Finish) {
    // The run's timers stop with it, so nothing would clear these later.
    pop = nil
    callout = nil
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
  /// A fill answers gaps: it offers the replies a gap counts.
  public var minShare: Double { GAP_SHARE }
}
