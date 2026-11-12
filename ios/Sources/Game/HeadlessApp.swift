import Book
import ChessCore
import Engine
import Foundation
import Model

/// The whole app without its screens: the same store, rounds and sittings the
/// app runs, driven by calls instead of taps, on a clock that moves only when
/// the game is waiting. Every action settles before it returns: the opponent
/// has replied, popups have come and gone, and what they said is in `signals`.
///
/// Make one with `HeadlessApp.run`, which also pins `Env`'s time and chance so a
/// game replays the same way every time.
@MainActor
public final class HeadlessApp: SignalSink {
  /// What's on screen.
  public enum Screen: String, Sendable {
    case welcome, onboarding, home, play, growth, playOn, endgame, middlegame
  }

  public enum Failure: Error, CustomStringConvertible {
    case notHere(String)
    case illegal(String)
    case refused(String)

    public var description: String {
      switch self {
      case .notHere(let what): return what
      case .illegal(let san): return "\(san) isn't legal here"
      case .refused(let san): return "\(san) wasn't taken"
      }
    }
  }

  public let store: AppStore
  public let clock: VirtualClock
  public let services: GameServices
  public let tree: OpeningTree
  public let index: ReferenceIndex

  /// Everything shown for a moment, in order, since the last `takeSignals`.
  public private(set) var signals: [GameSignal] = []

  public private(set) var play: PlaySession?
  public private(set) var growth: GrowthModel?
  public private(set) var endgame: EndgameSession?
  public private(set) var middlegame: MiddlegameSession?
  /// A game played on from the end of a Growth line, over the sitting.
  public private(set) var playOn: PlayOnGame?

  private init(store: AppStore, clock: VirtualClock, services: GameServices, tree: OpeningTree, index: ReferenceIndex) {
    self.store = store
    self.clock = clock
    self.services = services
    self.tree = tree
    self.index = index
    services.sink = self
  }

  /// Run `body` on a fresh headless app: a fresh install unless `storage` holds saves.
  /// `seed` fixes every draw of chance; `engine` makes each engine the game asks for.
  public static func run<T>(
    book: URL, seed: UInt32 = 1, storage: SaveStorage = MemoryStorage(),
    engine: @escaping @Sendable () -> ChessEngine = { ScriptedEngine() },
    _ body: (HeadlessApp) async throws -> T
  ) async throws -> T {
    let clock = VirtualClock()
    let millis = clock.millis
    let chance = LockedValue(seed)
    return try await Env.$clock.withValue({ millis.get() }) {
      try await Env.$chance.withValue({ chance.update(nextChance) }) {
        let app = try await launch(book: book, storage: storage, clock: clock, engine: engine)
        defer { app.close() }
        return try await body(app)
      }
    }
  }

  /// A headless app on `clock`. Use `run` unless `Env` is pinned some other way.
  public static func launch(
    book: URL, storage: SaveStorage = MemoryStorage(), clock: VirtualClock = VirtualClock(),
    engine: @escaping @Sendable () -> ChessEngine = { ScriptedEngine() }
  ) async throws -> HeadlessApp {
    let services = GameServices(clock: clock, makeEngine: engine)
    let store = AppStore(storage: storage, services: services, deviceName: "Headless")
    await store.load(book: book)
    guard let tree = store.tree, let index = store.index else { throw Failure.notHere("The book at \(book.path) couldn't be read") }
    let app = HeadlessApp(store: store, clock: clock, services: services, tree: tree, index: index)
    await app.idle()
    return app
  }

  public func emit(_ signal: GameSignal) { signals.append(signal) }

  /// The signals since the last call, cleared.
  public func takeSignals() -> [GameSignal] {
    defer { signals = [] }
    return signals
  }

  /// The callouts since the last `takeSignals`, as their words.
  public var callouts: [String] {
    signals.compactMap { if case .callout(let text, _) = $0 { return text } else { return nil } }
  }

  public var state: AppState { store.state }

  /* ── waiting ── */

  /// Let everything under way finish: engine searches, the opponent's reply, every beat on the clock.
  /// Stops at `limit` seconds of game time, so a game that never rests can't hang a test.
  public func idle(limit: Double = 600) async {
    let end = clock.now + limit
    while true {
      // Work that isn't waiting on the clock: an engine search, or a task about to run.
      // A real engine takes real time; a task stuck for two minutes is given up on.
      var spins = 0
      let started = Date()
      while services.busy > clock.sleeping && Date().timeIntervalSince(started) < 120 {
        spins += 1
        if spins < 50 { await Task.yield() } else { try? await Task.sleep(for: .milliseconds(1)) }
      }
      guard let next = clock.nextWake, next <= end else { return }
      clock.wakeNext()
      await Task.yield()
    }
  }

  /// A player taking `seconds` over a move: the clock moves on with nothing else happening.
  public func think(_ seconds: Double) async {
    await idle()
    clock.pass(seconds)
  }

  /* ── screens ── */

  public var screen: Screen {
    if !state.settings.seenIntro { return .welcome }
    if !state.settings.onboarded && play == nil { return .onboarding }
    if playOn != nil { return .playOn }
    if growth != nil { return .growth }
    if play != nil { return .play }
    if endgame != nil { return .endgame }
    if middlegame != nil { return .middlegame }
    return .home
  }

  /// The welcome pages, read.
  public func seeIntro() {
    store.update { $0.settings.seenIntro = true }
  }

  /// Onboarding's "Recommend some openings": its openings go in and the tutorial's first game starts.
  public func recommendOpenings() async {
    await startTutorial(RECOMMENDED_OPENINGS)
  }

  /// Onboarding with these openings: the tutorial's first game starts.
  public func startTutorial(_ openings: TutorialOpenings) async {
    seeIntro()
    store.startTutorial(openings)
    await openPlay()
  }

  /// Skip the tutorial, with a starter set's openings in the Playbook: on to Home.
  public func skipTutorial(starter id: String? = nil) throws {
    seeIntro()
    if let id {
      guard let set = STARTER_SETS.first(where: { $0.id == id }) else { throw Failure.notHere("No starter set \"\(id)\"") }
      store.update { $0.seed(tree, set) }
    }
    store.finishSkippedTutorial()
  }

  /// Skip the rest of the tutorial from Home.
  public func endTutorial() {
    store.update { $0.settings.skipTutorial() }
  }

  /// Home's selection: the side, Freeform or Drill, and the opening (by tree id or moves; nil for Any Opening).
  public func select(side: ColorChoice? = nil, start: RunStart? = nil, opening: String? = nil) throws {
    var node: String?
    if let opening {
      guard let found = tree.byId[opening] ?? deepestNodeAlong(tree, opening.split(separator: " ").map(String.init)) else {
        throw Failure.notHere("No opening \"\(opening)\"")
      }
      node = found.id
    }
    store.update { state in
      if let side { state.settings.selection.color = side }
      if let start { state.settings.start = start }
      if let node { state.settings.selection.opening = node }
    }
  }

  /// Change settings, as the Settings sheet would.
  public func settings(_ change: (inout Settings) -> Void) {
    store.update { change(&$0.settings) }
  }

  /// Home's Play: the next round starts, and the game settles.
  public func openPlay() async {
    closeModes()
    let session = PlaySession(store: store, tree: tree, index: index)
    play = session
    session.open()
    await idle()
  }

  /// Home's Recommendations, most needed first.
  public var recommendations: [Gap] { playbookGaps(state, tree) }

  /// Fill a recommendation in Growth.
  public func grow(_ gap: Gap) async throws {
    closeModes()
    guard let model = GrowthModel(gap: gap, store: store, tree: tree, index: index) else { throw Failure.notHere("That can't be grown") }
    growth = model
    await idle()
  }

  /// The end of a round's offer to grow, taken.
  public func grow(_ offer: GrowOffer) async throws {
    closeModes()
    guard let model = GrowthModel(offer: offer, store: store, tree: tree, index: index) else { throw Failure.notHere("That can't be grown") }
    growth = model
    await idle()
  }

  /// Endgames, on its library.
  public func openEndgames() {
    closeModes()
    endgame = EndgameSession(store: store)
  }

  /// Middlegame mode: a line drawn from your setup, or `line` exactly, built and started.
  public func openMiddlegame(line: MiddlegameLine? = nil) async {
    closeModes()
    let session = MiddlegameSession(store: store, tree: tree, index: index, exact: line)
    middlegame = session
    session.start(state.settings.middlegame, line: line)
    await idle()
  }

  /// Back Home from wherever: a finished Play round counts for the next one.
  public func home() async {
    closeModes()
    await idle()
  }

  private func closeModes() {
    playOn?.stop()
    playOn = nil
    play?.leave()
    play = nil
    growth?.leave()
    growth = nil
    endgame?.close()
    endgame = nil
    middlegame?.exit()
    middlegame = nil
  }

  private func close() {
    closeModes()
  }

  /* ── the board ── */

  /// The run on the board: Play's round or Middlegame's.
  public var run: RunModel? { play?.model ?? middlegame?.model }

  /// The board as it stands.
  public var fen: String? {
    if let playOn { return playOn.fen }
    if let growth { return growth.introFen ?? growth.fen }
    if let run { return run.shownFen }
    if let game = endgame?.game { return game.fen }
    return nil
  }

  /// The side you play on the board.
  public var side: ChessCore.Color? {
    if let playOn { return playOn.color }
    if let growth { return growth.run.color }
    if let run { return run.run.color }
    if let game = endgame?.game { return game.color }
    return nil
  }

  /// The moves played on the board.
  public var moves: [String] {
    if let playOn { return playOn.sans }
    if let growth { return growth.run.path }
    if let run { return run.run.played }
    if let game = endgame?.game { return game.moves }
    return []
  }

  /// Play a move on the board, by SAN, and let the game settle. While adding moves
  /// the move is added to the Playbook; in Growth it answers the hole or walks your prep.
  public func move(_ san: String) async throws {
    guard let fen else { throw Failure.notHere("No board") }
    guard let move = applySan(fen, san) else { throw Failure.illegal(san) }
    let before = (moves.count, growth?.session, endgame?.game?.moves.count)
    if let playOn {
      playOn.play(move)
    } else if let growth {
      growth.play(move)
    } else if let run {
      run.play(move)
    } else if let game = endgame?.game {
      game.play(move)
    }
    await idle()
    if before.0 == moves.count && before.1 == growth?.session && before.2 == endgame?.game?.moves.count && run?.finish == nil {
      throw Failure.refused(san)
    }
  }

  /// Several moves, each settled before the next.
  public func moves(_ sans: String) async throws {
    for san in sans.split(separator: " ") where !san.isEmpty { try await move(String(san)) }
  }

  /// The answers on offer while adding moves (in Play or Growth), best first.
  public var choices: [String] {
    if let growth { return growth.atHole ? growth.ranked.map(\.san) : [] }
    return run?.fillChoices.map(\.san) ?? []
  }

  /// Undo the last move added.
  public func undo() async {
    if let playOn { playOn.takeBack() } else if let growth { growth.undoLast() } else { run?.undoAdded() }
    await idle()
  }

  /// Done adding moves: the game goes on.
  public func doneAdding() async {
    run?.doneAdding()
    await idle()
  }

  /// Add moves at the hole the run stopped at.
  public func growHere() async {
    run?.growHere()
    await idle()
  }

  /// The X on a round under way: it ends here.
  public func endRound() async {
    run?.endRound()
    await idle()
  }

  /// Past a blunder, on to the end screen.
  public func continueToEnd() {
    run?.continueToEnd()
  }

  /// Next run: in Play, the next round, dealt; in Middlegame, another line; in Endgames, the next ending.
  public func next() async throws {
    if let play {
      if let model = play.model, model.finish != nil, play.deals(model) {
        _ = play.draw()
        play.dealt()
      } else {
        // Next run on a round under way: it ends where it stands, and the next follows.
        if let model = play.model, model.finish == nil {
          model.advancing = true
          model.endRound()
        }
        play.next()
      }
    } else if let middlegame {
      middlegame.start(state.settings.middlegame)
    } else if let endgame {
      endgame.next()
      boardEnding()
    } else {
      throw Failure.notHere("Nothing to go on to")
    }
    await idle()
  }

  /* ── Growth ── */

  /// Save Line: the sitting's moves go into the Playbook.
  public func saveGrowth() {
    growth?.save()
  }

  /// Another batch of moves, once a sitting has come to rest.
  public func addMore() async {
    growth?.addMore()
    await idle()
  }

  /// Play on from the end of the sitting's line against the engine. Nothing is recorded.
  public func playOnFromGrowth() async throws {
    guard let growth else { throw Failure.notHere("Growth isn't open") }
    playOn = PlayOnGame(from: growth.fen, color: growth.run.color, services: services)
    await idle()
  }

  /// Back from playing on, to the sitting.
  public func backToTheLine() {
    playOn?.stop()
    playOn = nil
  }

  /* ── Endgames ── */

  /// Practice: what's due, else the next ending.
  public func practice() async throws {
    guard let endgame else { throw Failure.notHere("Endgames isn't open") }
    guard endgame.practice() else { throw Failure.notHere("Nothing to practice") }
    boardEnding()
    await idle()
  }

  /// Play one ending by its id.
  public func playEnding(_ id: String) async throws {
    guard let endgame else { throw Failure.notHere("Endgames isn't open") }
    guard let entry = state.endgames.entries.first(where: { $0.id == id }) else { throw Failure.notHere("No ending \"\(id)\"") }
    endgame.play([entry])
    boardEnding()
    await idle()
  }

  /// Past the ending's card to its board, where the engine moves first if it's to move.
  private func boardEnding() {
    guard let game = endgame?.game else { return }
    game.toBoard()
    game.engineTurn()
  }

  /// Give the ending up.
  public func resign() async {
    endgame?.game?.resign()
    await idle()
  }
}

/// `mulberry32`, one step: the next number in [0, 1) and the state after it.
private func nextChance(_ seed: inout UInt32) -> Double {
  seed = seed &+ 0x6d2b_79f5
  var t = seed
  t = (t ^ (t >> 15)) &* (t | 1)
  t ^= t &+ ((t ^ (t >> 7)) &* (t | 61))
  return Double(t ^ (t >> 14)) / 4_294_967_296
}
