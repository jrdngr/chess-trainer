import Book
import ChessCore
import Engine
import Model
import Observation

/// The scan behind Tidy, over the whole Playbook. Shared by the Playbook
/// tab's Tidy button and Tidy itself, so the count and the list are the same
/// piece of work.
@MainActor @Observable
public final class TidyScan {
  @ObservationIgnored private unowned let services: GameServices
  /// The positions where another move reaches your lines; nil until the first scan is whole.
  public private(set) var choices: [TidyChoice]?
  @ObservationIgnored private var scanned: Input?

  public init(services: GameServices) {
    self.services = services
  }

  /// What a scan depends on.
  public struct Input: Equatable {
    public var playbooks: [String: Playbook]
    public var order: [String]
    public var minShare: Double

    public init(playbooks: [String: Playbook], order: [String], minShare: Double) {
      self.playbooks = playbooks
      self.order = order
      self.minShare = minShare
    }

    public init(_ state: AppState) {
      self.init(playbooks: state.playbooks, order: state.playbookOrder, minShare: AUTO_GROWTH.minShare)
    }
  }

  /// Scan again when the Playbook changed; a rescan keeps the last list until it is whole.
  public func run(_ input: Input, _ index: ReferenceIndex) async {
    if input == scanned { return }
    let reps = input.order.compactMap { input.playbooks[$0] }
    let opts = TidyOptions(minShare: input.minShare)
    let found = await Task.detached(priority: .userInitiated) {
      tidyPositions(reps).compactMap { choiceAt($0.rep, index, $0.node, opts) }
    }.value
    if Task.isCancelled { return }
    scanned = input
    choices = found
  }

  /// What a move gives up against the best: the book's table, else the engine, asked once.
  public func loss(_ fen: String, _ san: String) -> Double? {
    guard let move = applySan(fen, san) else { return .infinity }
    if let book = BookScores.score(fen, move.uci) { return Double(book.lost) }
    switch services.checks.check(fen, san) {
    case .none:
      services.checks.askCheck(fen, san)
      return nil
    case .some(.none): return .infinity
    case .some(.some(let check)): return check.lost
    }
  }

  /// The finds for the Playbook as it is, most moves removed first. Choices
  /// the engine has not judged yet are left out until it has, and so are
  /// moves on the way to an opening you own, which Tidy can't take.
  public func finds(_ state: AppState, _ index: ReferenceIndex) -> [TidyFind] {
    sortFinds((choices ?? []).compactMap { choice in
      guard let rep = state.playbooks[choice.playbookId], rep.nodes[choice.nodeId] != nil,
        state.canDelete(choice.color, choice.path + [choice.mine]),
        case .find(let find) = decide(rep, index, choice, loss)
      else { return nil }
      return find
    })
  }

  /// How many finds Tidy lists right now; nil before the first scan is whole.
  public func count(_ state: AppState, _ index: ReferenceIndex) -> Int? {
    choices == nil ? nil : finds(state, index).count
  }
}
