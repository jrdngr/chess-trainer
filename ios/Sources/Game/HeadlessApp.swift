import Book
import ChessCore
import Engine
import Foundation
import Model

/// The whole app without its screens: the same store, rounds and modes the
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
    case welcome, onboarding, home, play, endgame, middlegame
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
  public private(set) var endgame: EndgameSession?
  public private(set) var middlegame: MiddlegameSession?

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
    if play != nil { return .play }
    if endgame != nil { return .endgame }
    if middlegame != nil { return .middlegame }
    return .home
  }

  /// The welcome pages, read.
  public func seeIntro() {
    store.update { $0.settings.seenIntro = true }
  }

  /// Welcome's "Recommend some openings": the recommended set goes in and the first Play game starts.
  public func recommendOpenings() async {
    seeIntro()
    store.recommendOpenings()
    await openPlay()
  }

  /// Welcome's "Choose my openings": an opening from the list for each slot (White, Black against
  /// 1.e4, Black against 1.d4), by id, then the first Play game starts.
  public func chooseOpenings(_ ids: [String]) async throws {
    for id in ids where curatedOpening(id) == nil { throw Failure.notHere("No opening \"\(id)\" on the list") }
    var choosing = Choosing()
    for id in ids where !choosing.pick(id) {
      throw Failure.notHere("Pick one opening for each slot in order: a White one, one against 1.e4, then one against 1.d4")
    }
    guard let picked = choosing.ids, picked.count == ids.count else {
      throw Failure.notHere("Pick one opening for each slot in order: a White one, one against 1.e4, then one against 1.d4")
    }
    seeIntro()
    store.chooseOpenings(picked)
    await openPlay()
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
    if let side, side != .w, !state.owns(.sidePicker) { throw Failure.notHere("Black is locked: the side picker is in the Pawn Shop") }
    if start == .freeform, !state.owns(.freeform) { throw Failure.notHere("Freeform is locked: it is in the Pawn Shop") }
    if let node, node != ANY_OPENING, !state.owns(.openingPicker) { throw Failure.notHere("Openings are locked: the opening picker is in the Pawn Shop") }
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

  /// Home's Play: the next round starts, and the game settles. With `grow`, an opening page's Grow:
  /// the first round starts at that gap and grows there.
  public func openPlay(grow: Gap? = nil) async {
    closeModes()
    let session = PlaySession(store: store, tree: tree, index: index, grow: grow)
    play = session
    session.open()
    await idle()
  }

  /// Home's Next line: what the Playbook grows next, and in how many runs.
  public var nextUp: (name: String, runs: Int)? { nextOpening(state, tree) }

  /// The Playbook tab's tree for one side.
  public func map(_ side: ChessCore.Color) -> [MapNode] { playbookMap(state, tree, side: side) }

  /// An opening of yours on the tree, as its page shows it.
  public func page(_ node: MapNode) -> NodePage { nodePage(state, tree, side: node.color, id: node.id, line: node.line) }

  /// Grow from an opening's page: a Play run at the hole under it the curve allows now.
  public func grow(_ node: MapNode) async throws {
    guard case .ready(let gap) = page(node).grow else { throw Failure.notHere("Nothing under \(node.name) can grow yet") }
    await openPlay(grow: gap)
  }

  /// Delete from an opening's page; the undo puts it back.
  public func delete(_ node: MapNode) throws -> PlaybookUndo {
    var undo: PlaybookUndo?
    store.update { undo = $0.removeNodeAt(node.color, node.line) }
    guard let undo else { throw Failure.notHere("\(node.name) isn't in your Playbook") }
    return undo
  }

  public func undo(_ undo: PlaybookUndo) { store.update { $0.undo(undo) } }

  /// Tidy's list, once the scan and the engine are done with it.
  public func tidyFinds() async -> [TidyFind] {
    await services.tidy.run(TidyScan.Input(state), index)
    // The engine is asked as the list is read; read again until nothing waits.
    while true {
      let before = services.checks.checks.count
      _ = services.tidy.finds(state, index)
      await idle()
      if services.checks.checks.count == before { break }
    }
    return services.tidy.finds(state, index)
  }

  /// The Playbook tab's Tidy count: nil before the scan is whole.
  public var tidyCount: Int? { services.tidy.count(state, index) }

  /// Switch these moves, from a Tidy card; the undo puts them back.
  public func tidySwitch(_ find: TidyFind) throws -> PlaybookUndo {
    var undo: PlaybookUndo?
    store.update { undo = $0.tidySwitch(find.playbookId, find.nodeId, find.suggestion) }
    guard let undo else { throw Failure.notHere("\(find.suggestion) can't be played there") }
    return undo
  }

  /// Buy an opening for sale on the tree, at its side's price.
  public func buyFamily(_ node: MapNode) throws {
    guard let id = node.family, node.forSale else { throw Failure.notHere("\(node.name) isn't for sale") }
    var bought = false
    store.update { bought = $0.buyFamily(id, tree) }
    if !bought { throw Failure.notHere("\(node.name) needs \(state.families.price(node.color)) pawns") }
  }

  /// Swap an opening you have (by id) for one for sale, with a swap token.
  public func swapFamily(_ out: String, for node: MapNode) throws {
    guard let id = node.family, node.forSale else { throw Failure.notHere("\(node.name) isn't for sale") }
    var swapped = false
    store.update { swapped = $0.swapFamily(out, for: id, tree) }
    if !swapped { throw Failure.notHere("No swap: \(state.families.tokens) token\(state.families.tokens == 1 ? "" : "s") held") }
  }

  /// A cash purchase as the App Store would complete it, as a new transaction.
  public func purchase(_ product: CashProduct) {
    store.credit(product, transaction: "headless-\(state.credited.count + 1)")
  }

  /// Buy an item in the Pawn Shop.
  public func buy(_ id: String) throws {
    guard let item = shopItem(id) else { throw Failure.notHere("No item \"\(id)\" in the Pawn Shop") }
    switch state.status(item) {
    case .buyable: store.buy(id)
    case .owned: throw Failure.notHere("\(item.name) is already yours")
    case .short(let by): throw Failure.notHere("\(item.name) needs \(by) more pawn\(by == 1 ? "" : "s")")
    case .locked: throw Failure.notHere("\(item.name) needs \(item.needs.compactMap { shopItem($0)?.name }.joined(separator: " and ")) first")
    case .soon: throw Failure.notHere("\(item.name) isn't for sale yet")
    }
  }

  /// Endgames, on its library.
  public func openEndgames() throws {
    guard state.owns(.endgames) else { throw Failure.notHere("Endgames is locked: it is in the Pawn Shop") }
    closeModes()
    endgame = EndgameSession(store: store)
  }

  /// Middlegame mode: a line drawn from your setup, built and started.
  public func openMiddlegame() async throws {
    guard state.owns(.middlegame) else { throw Failure.notHere("Middlegame is locked: it is in the Pawn Shop") }
    closeModes()
    let session = MiddlegameSession(store: store, tree: tree, index: index)
    middlegame = session
    session.start(state.settings.middlegame)
    await idle()
  }

  /// Back Home from wherever: a finished Play round counts for the next one.
  public func home() async {
    closeModes()
    await idle()
  }

  private func closeModes() {
    play?.leave()
    play = nil
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
    if let run { return run.shownFen }
    if let game = endgame?.game { return game.fen }
    return nil
  }

  /// The side you play on the board.
  public var side: ChessCore.Color? {
    if let run { return run.run.color }
    if let game = endgame?.game { return game.color }
    return nil
  }

  /// The moves played on the board.
  public var moves: [String] {
    if let run { return run.run.played }
    if let game = endgame?.game { return game.moves }
    return []
  }

  /// Play a move on the board, by SAN, and let the game settle. While adding moves
  /// the move is added to the Playbook.
  public func move(_ san: String) async throws {
    guard let fen else { throw Failure.notHere("No board") }
    guard let move = applySan(fen, san) else { throw Failure.illegal(san) }
    let before = (moves.count, endgame?.game?.moves.count)
    if let run {
      run.play(move)
    } else if let game = endgame?.game {
      game.play(move)
    }
    await idle()
    if before.0 == moves.count && before.1 == endgame?.game?.moves.count && run?.finish == nil && run?.heldBlunder == nil {
      throw Failure.refused(san)
    }
  }

  /// Several moves, each settled before the next.
  public func moves(_ sans: String) async throws {
    for san in sans.split(separator: " ") where !san.isEmpty { try await move(String(san)) }
  }

  /// The answers on offer while adding moves, best first.
  public var choices: [String] {
    return run?.fillChoices.map(\.san) ?? []
  }

  /// Undo the last move added.
  public func undo() async {
    run?.undoAdded()
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

  /// Continue after a blunder: it is taken back for its pawns, once a run.
  public func buyContinue() async throws {
    guard let run, run.canContinue else { throw Failure.notHere("No Continue here") }
    run.buyContinue()
    await idle()
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
