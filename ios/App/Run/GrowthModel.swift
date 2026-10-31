import Book
import ChessCore
import Foundation
import Model
import Observation

/// One batch of Growth, grown from the end of a run: `GrowthScreen.tsx`'s
/// launch, driven through GrowthController.
@MainActor @Observable
final class GrowthModel {
  let offer: GrowOffer
  let index: ReferenceIndex
  let tree: OpeningTree
  private let store: AppStore
  /// The tree as it was when the sitting began, so adding cannot re-steer it.
  private let start: Repertoire
  private let find: GrowthOptions
  private(set) var session: GrowthSession
  private(set) var toast: String?
  private var logged = false

  init?(offer: GrowOffer, store: AppStore, tree: OpeningTree, index: ReferenceIndex) {
    guard let rep = store.state.repertoires[offer.launch.row.repertoireId] else { return nil }
    self.offer = offer
    self.store = store
    self.tree = tree
    self.index = index
    start = rep
    let widened = offer.launch.widened
    find = GrowthOptions(minShare: widened?.minShare ?? AUTO_GROWTH.minShare, maxPly: widened?.maxPly ?? AUTO_GROWTH.maxPly)
    session = beginGrowth(rep, offer.launch.row, offer.launch.hole)
    settle()
  }

  var maxPly: Int { find.maxPly ?? AUTO_GROWTH.maxPly }
  var allowance: Int { allowanceOf(session, maxPly) }
  var added: Int { inBatch(session) }
  var choices: [Reply] { session.phase == .hole ? choicesAt(index, session.run.fen, 4) ?? [] : [] }
  var done: Bool { session.phase == .done || session.phase == .lost }
  var fen: String { session.answer?.after ?? session.run.fen }

  func pick(_ san: String) {
    apply(choose(session, san, allowance, choices.map(\.san)))
  }

  func undoLast() { apply(undo(session, store.state.repertoires[start.id])) }

  func finish() {
    session = stop(session)
    logRound()
  }

  /// What happens on its own between taps, as the screen settles it.
  private func settle() {
    for _ in 0..<200 {
      let before = session
      if session.phase == .walking {
        session = opponentToMove(session, start)
          ? opponentWalks(session, start, index, find)
          : nothingPrepared(session, preparedHere(start, session.run).count)
      }
      if (session.phase == .hole || session.phase == .answered) && pastTheBook(index, session.run.fen) {
        apply(reachedEdge(session), settling: false)
      }
      if session.phase == .hole {
        session = choices.isEmpty ? stop(session) : measureBatch(session, maxPly)
      }
      if session.phase == .answered, let hole = nextHole(index, session.run) {
        session = theyReply(session, hole)
      }
      if session == before { break }
    }
    if done { logRound() }
  }

  private func apply(_ step: GrowthStep, settling: Bool = true) {
    session = step.session
    let rid = start.id
    for effect in step.effects {
      switch effect {
      case .addLine(let line): store.update { $0.addGrowthLine(rid, line, index) }
      case .removeLine(let id): store.update { $0.removeLine(rid, id) }
      case .toast(let text): show(text)
      case .edgeFlash: show("End of the book")
      case .buzz(let ms): Haptics.buzz(ms, on: store.state.settings.hapticFeedback)
      case .log: break
      }
    }
    if settling { settle() }
  }

  /// One sitting is one round, logged once it is at rest.
  private func logRound() {
    guard !logged, let round = growthRound(session, tree, offer.launch.opening, allowance, at: Env.now()) else { return }
    logged = true
    store.update { $0.endRound(tree, round) }
  }

  private func show(_ text: String) {
    toast = text
    Task { @MainActor [weak self] in
      try? await Task.sleep(for: .seconds(1.6))
      if self?.toast == text { self?.toast = nil }
    }
  }
}
