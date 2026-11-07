import Book
import Model
import Observation

/// The scan behind Tidy, over the selection: every find. Shared by the
/// Playbook's Tidy row and Tidy itself, so its count and the list are the
/// same piece of work.
@MainActor @Observable
final class TidyScan {
  /// Nil while the first scan runs; a rescan keeps showing the last list until it is whole.
  private(set) var finds: [TidyFind]?
  private(set) var looking: Int?

  /// What a scan depends on.
  struct Input: Equatable {
    var repertoires: [String: Repertoire]
    var order: [String]
    var selection: Selection
    var growth: GrowthPrefs
  }

  /// Off-book finds put to the engine at once, from the top of the list.
  static let checkAhead = 12

  func run(_ input: Input, _ tree: OpeningTree, _ index: ReferenceIndex) async {
    let regions = regionsBySide(tree, input.selection)
    let reps = repertoiresIn(input.order.compactMap { input.repertoires[$0] }, input.selection.color)
    let opts = TidyOptions(prefs: NudgePrefs(priority: input.growth.nudgePriority, pawns: input.growth.nudgePawns), minShare: input.growth.minShare)
    let todo = acrossRegions(regions, reps, { rep, node in tidyPositions([rep], tree, node) }, { "\($0.rep.id):\($0.node.id)" })
    looking = todo.count
    let found = await Task.detached(priority: .userInitiated) {
      sortFinds(todo.compactMap { findAt($0.rep, index, $0.node, opts) })
    }.value
    if Task.isCancelled { return }
    finds = found
    looking = nil
    ask(found)
  }

  /// Puts the first off-book finds of a list to the engine.
  func ask(_ list: [TidyFind]) {
    for find in list.filter(\.offBook).prefix(Self.checkAhead) { EngineChecks.shared.askSound(find.fen, find.suggestion) }
  }

  /// The finds to show: an off-book move waits on the engine, and one it fails drops out.
  func shown(_ list: [TidyFind]) -> [TidyFind] {
    list.filter { !$0.offBook || EngineChecks.shared.isSound($0.fen, $0.suggestion) != false }
  }

  /// How many things Tidy would list right now, or nil while it is still looking.
  var count: Int? {
    guard looking == nil, let finds else { return nil }
    return shown(finds).count
  }
}
