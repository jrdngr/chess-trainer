import ChessCore
import Foundation
import Model
import Observation

/// A sitting of Drill positions, driven through the drill controller: the
/// screen half of `DrillSession.tsx`. It owns the clock, the flash's timer
/// and the store's side of each effect.
@MainActor @Observable
final class DrillSessionModel {
  let items: [TrainingItem]
  let title: String
  let prefs: DrillPrefs
  let openingId: String
  let tree: OpeningTree
  let clock: MoveClock
  let intro: RoundIntro?
  private let store: AppStore
  private let opts: DrillOptions
  @ObservationIgnored private let rand: () -> Double
  @ObservationIgnored private var logged = false
  private(set) var drill: DrillState
  var revealLine = false
  var showMoves = false
  var explore = false { didSet { syncClock() } }
  var why = false

  init(items: [TrainingItem], mode: SessionMode, title: String, prefs: DrillPrefs, openingId: String?, store: AppStore, tree: OpeningTree) {
    self.items = items
    self.title = title
    self.prefs = prefs
    self.store = store
    self.tree = tree
    let opening = openingId ?? store.state.settings.selection.opening
    self.openingId = opening
    opts = DrillOptions(mode: mode, maxNew: prefs.newPerSession, weakFirst: prefs.weakFirst)
    rand = mulberry32(seed: (Env.random() * 2_147_483_648).rounded(.down))
    clock = MoveClock(seconds: clockSeconds(prefs.clock))
    let begun = beginDrill(items, store.state.cards, opts, Env.now())
    drill = begun
    intro = begun.queue.first.map { first in
      let catalog = store.catalog
      let named = deepestNodeWithin(tree, nodeById(tree, opening), first.pathSans).id
      let trail = catalog.map { selectionTrail(tree, $0, named) } ?? []
      return RoundIntro(mode: "Drill positions", trail: trail, path: first.pathSans, autoplay: store.state.settings.autoplay)
    }
    restock()
  }

  var item: TrainingItem? { current(drill) }
  var side: ChessCore.Color { item?.orientation ?? .w }
  var held: Bool { intro?.held ?? false }
  var card: Card? { item.flatMap { store.state.cards[$0.cardId] } }
  /// Practice past the schedule, not a review.
  var extra: Bool { card.map { $0.stage == .review && $0.due > Env.now() } ?? false }
  var expectedMove: LegalMove? { item.flatMap { i in expectedSan(i).flatMap { applySan(i.fen, $0) } } }
  var preferred: ExpectedMove? { item.flatMap { i in drill.played.flatMap { checkAnswer(i, $0.san).preferred } } }

  var boardFen: String {
    guard let item else { return "" }
    guard drill.phase != .ask, let played = drill.played else { return item.fen }
    if drill.phase == .wrong { return revealLine ? expectedMove?.after ?? item.fen : item.fen }
    return played.after
  }

  func begin() {
    intro?.begin()
    #if DEBUG
      debugPlay()
    #endif
    syncClock()
    Task { [weak self] in
      while let self, self.held {
        try? await Task.sleep(for: .milliseconds(150))
        self.syncClock()
      }
      self?.syncClock()
    }
  }

  func play(_ move: LegalMove) {
    guard let item, drill.phase == .ask else { return }
    let followUp = prefs.followLine ? followUpFor(item, items, store.state.repertoires[item.repertoireId]) : nil
    run(answer(drill, move, clock.elapsedNow(), card, followUp))
  }

  func continueAfterMiss() {
    revealLine = false
    showMoves = false
    set(continueAfterWrong(drill))
  }

  func regrade(_ value: Grade) { run(regradeLast(drill, value)) }

  /// End the sitting: log what was answered, if anything.
  func stop() {
    log()
    clock.stop()
    intro?.stop()
  }

  private func next(_ extra: TrainingItem?) {
    revealLine = false
    showMoves = false
    set(advance(drill, extra))
  }

  private func set(_ next: DrillState) {
    drill = next
    restock()
  }

  /// Keep the queue stocked, and the card for the position in front of you made.
  private func restock() {
    let stocked = refill(drill, items, store.state.cards, opts, rand, Env.now())
    if stocked != drill { drill = stocked }
    if let item, store.state.cards[item.cardId] == nil { store.update { $0.ensureCard(item) } }
    syncClock()
  }

  private func syncClock() {
    clock.sync(key: "\(drill.index):\(item?.cardId ?? "")", active: drill.phase == .ask && item != nil && !explore && !showMoves && !held)
  }

  /// Do what the controller asks, in order.
  private func run(_ step: DrillStep) {
    drill = step.state
    syncClock()
    for effect in step.effects {
      switch effect {
      case .record(let line, let color, let correct):
        store.update { _ = $0.recordMove(tree, MoveResult(mode: .drill, line: line, color: color, correct: correct, rated: false, at: Env.now()), []) }
      case .buzz(let pattern): Haptics.buzz(pattern.first ?? 0, on: store.state.settings.hapticFeedback)
      case .grade(let item, let grade, let played, let correct): store.update { $0.grade(item, grade, played, correct) }
      case .regrade(let item, let before, let grade, let played): store.update { $0.regrade(item, before, grade, played) }
      case .mistake(let mistake): store.update { $0.logMistake(mistake) }
      case .flash(let next):
        // A beat on the move just made, so it registers before the board changes.
        Task { [weak self] in
          try? await Task.sleep(for: .milliseconds(650))
          self?.next(next)
        }
      }
    }
    restock()
  }

  private func log() {
    guard !logged, let round = drillRound(drill, openingId) else { return }
    logged = true
    store.update { $0.endRound(tree, round) }
  }
}
