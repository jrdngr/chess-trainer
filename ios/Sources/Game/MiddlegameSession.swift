import Book
import ChessCore
import Engine
import Model
import Observation

/// A line your Playbook asked for, to play out exactly: from the opening sheet.
public struct MiddlegameLine: Equatable, Sendable {
  public var color: ChessCore.Color
  public var sans: [String]
  /// The line ends on a reply your Playbook can't meet: you take over there.
  public var gap = false

  public init(color: ChessCore.Color, sans: [String], gap: Bool = false) {
    self.color = color
    self.sans = sans
    self.gap = gap
  }
}

/// Middlegame mode: one of your lines played out to a middlegame, then a Run
/// run from there. While the handoff is built, the mode is announced.
@MainActor @Observable
public final class MiddlegameSession {
  public let tree: OpeningTree
  public let index: ReferenceIndex
  /// The exact line to play out; nil to draw one from your setup each run.
  public let exact: MiddlegameLine?
  @ObservationIgnored private let store: AppStore

  public private(set) var model: RunModel?
  /// The handoff being built, named by the opening it is in.
  public private(set) var building: [String]?
  /// The line the last run played out, for Same line.
  public private(set) var last: MiddlegameLine?
  /// A run couldn't start: what to say, and whether the mode should close.
  @ObservationIgnored public var onFail: ((_ message: String, _ close: Bool) -> Void)?
  @ObservationIgnored private var job: Task<Void, Never>?

  public init(store: AppStore, tree: OpeningTree, index: ReferenceIndex, exact: MiddlegameLine? = nil) {
    self.store = store
    self.tree = tree
    self.index = index
    self.exact = exact
  }

  private var services: GameServices { store.services }

  /// Draw a line from the setup (or take `line`), build its handoff, then begin the run there.
  /// A run from the opening sheet draws its next lines through that line's own opening.
  public func start(_ saved: RunPrefs, line: MiddlegameLine? = nil) {
    let prefs = middlegamePrefs(saved)
    let selection = (line ?? exact).map(selectionOf) ?? store.takeRoundSelection()
    let seed = (Env.random() * 2_147_483_648).rounded(.down)
    var options = runStart(prefs, selection, store.state, tree, seed: seed)
    guard let drawn = line ?? startRun(options).map({ begun -> MiddlegameLine in
      let yours = middlegameLine(begun, store.state.playbookList)
      return MiddlegameLine(color: begun.state.run.color, sans: yours.sans, gap: yours.gap)
    }),
      !drawn.sans.isEmpty
    else {
      services.emit(.toast("No line to play out here"))
      onFail?("No line to play out here", exact != nil && model == nil)
      return
    }
    options.color = drawn.color == .w ? .w : .b
    model?.stop()
    model = nil
    last = drawn
    building = trail(drawn.sans)
    let tools = handoffTools(services.engine("middlegame-builder"), index, prefs.opponentLevel(store.state.strength))
    let engine = services.engine("middlegame")
    let clock = services.clock
    job?.cancel()
    job = services.spawn { [weak self] in
      let began = clock.now
      let handoff = await buildHandoff(drawn.sans, color: drawn.color, tools: tools, seed: seed, gap: drawn.gap)
      // The announcement holds at least as long as Run's, however quick the build.
      let left = RunModel.announceMs - (clock.now - began)
      if left > 0 { await clock.sleep(left) }
      guard let self, !Task.isCancelled else { return }
      self.building = nil
      guard let handoff,
        let run = RunModel(
          middlegame: options, handoff: handoff, prefs: prefs, selection: selection,
          store: self.store, tree: self.tree, index: self.index, engine: engine)
      else {
        self.services.emit(.toast("This line couldn't be played out"))
        self.onFail?("This line couldn't be played out", self.exact != nil)
        return
      }
      self.model = run
      run.start()
    }
  }

  /// The opening a line is in and its side, as a selection to draw from.
  private func selectionOf(_ line: MiddlegameLine) -> Selection {
    Selection(color: line.color == .w ? .w : .b, opening: deepestNodeAlong(tree, line.sans)?.id ?? tree.root.id)
  }

  /// The opening the line is in, as the announcement names it.
  private func trail(_ sans: [String]) -> [String] {
    let node = deepestNodeWithin(tree, tree.root, sans)
    guard let catalog = store.catalog else { return [node.name] }
    return selectionTrail(tree, catalog, node.id)
  }

  /// Change options: back to the setup screen.
  public func setup() {
    model?.stop()
    model = nil
  }

  /// Leaving the mode: the build and the run stop.
  public func exit() {
    job?.cancel()
    model?.stop()
  }
}
