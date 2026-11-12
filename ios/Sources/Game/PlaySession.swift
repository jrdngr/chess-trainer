import Book
import Engine
import Model
import Observation

/// Play: one round after another, each a run decided for you. A finished
/// round stays on its board and the next is drawn from the deck; Next run goes
/// straight on; Home ends the session. The tutorial plays its games in order,
/// and an empty Playbook starts a first game as White, adding moves from move 1.
@MainActor @Observable
public final class PlaySession {
  public let tree: OpeningTree
  public let index: ReferenceIndex
  @ObservationIgnored private let store: AppStore

  /// The round on the board.
  public private(set) var model: RunModel?
  /// Nothing to practice: the Playbook has no lines in the selection.
  public private(set) var nothing = false
  /// The round drawn from the deck, ready to take over once its card is on the board.
  public private(set) var upcoming: RunModel?
  /// The finished round's start is already counted for the next one.
  @ObservationIgnored private var counted = false

  public init(store: AppStore, tree: OpeningTree, index: ReferenceIndex) {
    self.store = store
    self.tree = tree
    self.index = index
  }

  private var engine: ChessEngine { store.services.engine("play") }

  /// The first round, unless one is under way.
  public func open() {
    if model == nil && !nothing { begin() }
  }

  /// A finished Play round stays on its board and deals the next from the deck. The tutorial's games don't.
  public func deals(_ model: RunModel) -> Bool { model.round != nil && model.tutorialGame == nil }

  /// The next round, picked when it starts: what the last one changed is in the store by then.
  private func begin() {
    guard let run = make() else {
      nothing = true
      return
    }
    model = run
    run.start()
  }

  /// The next round's run, not yet started.
  private func make() -> RunModel? {
    // The tutorial's next game, whatever is selected.
    if let game = store.state.settings.tutorial?.next {
      return RunModel(tutorial: game, store: store, tree: tree, index: index, engine: engine)
    }
    if store.state.playbooks.values.allSatisfy({ $0.nodes.isEmpty }) {
      return RunModel(firstGame: store, tree: tree, index: index, engine: engine)
    }
    let selection = store.takeRoundSelection()
    guard let round = nextRound(store.state, tree, selection, store.autoHistory) else { return nil }
    return RunModel(round: round, selection: selection, store: store, tree: tree, index: index, engine: engine)
  }

  /// The deck was touched: the next round, picked now, to deal. Nil when there is none.
  public func draw() -> RunModel? {
    if upcoming == nil {
      count()
      upcoming = make()
    }
    return upcoming
  }

  /// The drawn card is on the board: its round takes over, straight onto the board.
  public func dealt() {
    guard let run = upcoming else { return next() }
    model?.stop()
    upcoming = nil
    counted = false
    run.start(dealt: true)
    model = run
  }

  /// The finished round's start counted for the next one, once.
  private func count() {
    guard !counted, let model, let round = model.round else { return }
    store.autoHistory = afterRound(store.autoHistory, round, model.selection)
    counted = true
  }

  /// Home after a finished round, its start counted for the next one.
  public func home() {
    count()
    exit()
  }

  /// The X: Home from a finished round counts it; from one under way it just leaves.
  public func leave() {
    if model?.finish != nil { home() } else { exit() }
  }

  /// Next run: straight on to the next round, its start counted like a finished one's.
  public func next() {
    count()
    model?.stop()
    model = nil
    upcoming = nil
    counted = false
    begin()
  }

  /// Leaving Play: the round stops where it stands.
  public func exit() {
    model?.stop()
  }
}
