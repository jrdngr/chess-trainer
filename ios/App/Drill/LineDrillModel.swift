import Book
import ChessCore
import Foundation
import Model
import Observation

/// Drill a line at a time, driven through `LineDrillController`.
/// It owns the timers, the clock and drawing lines.
@MainActor @Observable
final class LineDrillModel {
  typealias L = LineDrillController
  /// Lines drawn at a time in a sitting with no end.
  static let BATCH = 5

  let color: ChessCore.Color
  let openingId: String
  let prefs: DrillPrefs
  let count: Int?
  let clock: MoveClock
  private(set) var intro: RoundIntro?
  private(set) var lines: LineDrillState
  var why = false { didSet { syncClock() } }
  private let budget: Int?
  private let lean: LineLean
  private let only: Set<String>?
  private let store: AppStore
  private let tree: OpeningTree
  private let index: ReferenceIndex
  private let region: OpeningNode
  @ObservationIgnored private let rand: () -> Double
  @ObservationIgnored private var reply: Task<Void, Never>?

  init(
    color: ChessCore.Color, openingId: String, lean: LineLean, prefs: DrillPrefs, count: Int? = nil, budget: Int? = nil,
    only: Set<String>? = nil, store: AppStore, tree: OpeningTree, index: ReferenceIndex
  ) {
    self.color = color
    self.openingId = openingId
    self.lean = lean
    self.prefs = prefs
    self.count = count
    self.budget = budget
    self.only = only
    self.store = store
    self.tree = tree
    self.index = index
    region = nodeById(tree, openingId)
    rand = mulberry32(seed: (Env.random() * 2_147_483_648).rounded(.down))
    clock = MoveClock(seconds: clockSeconds(prefs.clock))
    lines = L.begin([])
    lines = L.begin(draw())
    if let line = lines.line {
      let named = region.depth > 0 ? openingId : deepestNodeWithin(tree, region, line.sans).id
      let trail = store.catalog.map { selectionTrail(tree, $0, named) } ?? []
      intro = RoundIntro(mode: "Drill lines", trail: trail, path: [], autoplay: store.state.settings.autoplay)
    }
  }

  var grouped: Bool { prefs.batchSimilar }
  var mine: Bool { L.yourMove(lines, color) }
  var held: Bool { intro?.held ?? false }
  var moved: Bool { lines.finished > 0 || !lines.times.isEmpty || lines.misses > 0 }
  var fens: [String] { lines.line.map { walkSan($0.sans).fens } ?? [] }
  var fen: String { fens.isEmpty ? "" : fens[min(lines.ply, fens.count - 1)] }
  var expected: String? { L.expectedHere(lines, color) }
  var expectedMove: LegalMove? { expected.flatMap { applySan(fen, $0) } }
  var boardFen: String { lines.phase == .flash ? lines.played?.after ?? fen : fen }
  var lastOfRound: Bool { count != nil && lines.at + 1 >= lines.batch.count }

  func begin() {
    intro?.begin()
    #if DEBUG
      debugPlay()
    #endif
    settle()
    Task { [weak self] in
      while let self, self.held {
        try? await Task.sleep(for: .milliseconds(150))
      }
      self?.settle()
    }
  }

  func stop() {
    reply?.cancel()
    clock.stop()
    intro?.stop()
  }

  func play(_ move: LegalMove) {
    guard let line = lines.line, let rep = store.state.repertoires[line.repertoireId] else { return }
    let key = positionKey(fen)
    let item = mine ? allItems([rep]).first { $0.key == key } : nil
    run(L.answer(lines, color, move, clock.elapsedNow(), rep, item, store.state.mistakes.map(\.id)))
  }

  /// After a miss: your prep's move is played, and the line goes on.
  func carryOnAfterMiss() {
    why = false
    set(L.carryOn(lines))
  }

  func regrade(_ value: Grade) { run(L.regrade(lines, value)) }

  func nextLine() {
    let fresh = L.needsDraw(lines) ? draw(grouped ? Set(lines.batch.map(\.tipId)) : nil) : nil
    set(L.nextLine(lines, fresh))
  }

  private func draw(_ avoid: Set<String>? = nil) -> [DrillLine] {
    guard let rep = store.state.repertoireList.first(where: { $0.color == color }) else { return [] }
    return drawLines(DrawOptions(
      rep: rep, tree: tree, region: region, index: index, lean: lean, cards: store.state.lineCards, draw: prefs.draw, only: only,
      avoid: avoid, count: count ?? (grouped ? MAX_LINES : Self.BATCH), budget: budget ?? (grouped ? LINE_BUDGET : nil),
      similar: grouped, rand: rand))
  }

  private func set(_ next: LineDrillState) {
    lines = next
    settle()
  }

  /// What happens on its own: the opponent's moves after a beat, and the line's end at once.
  private func settle() {
    syncClock()
    reply?.cancel()
    guard let line = lines.line, lines.phase == .play, !held else { return }
    if !mine && lines.ply < line.sans.count {
      reply = Task { [weak self] in
        try? await Task.sleep(for: .milliseconds(450))
        guard let self, !Task.isCancelled else { return }
        self.set(L.theirMove(self.lines, self.color))
      }
      return
    }
    let done = L.lineDone(lines, color, tree, region)
    if done.state != lines { run(done) }
  }

  private func syncClock() {
    clock.sync(key: "\(lines.at):\(lines.ply):\(lines.finished)", active: lines.phase == .play && mine && !why && !held)
  }

  /// Do what the controller asks, in order.
  private func run(_ step: LineStep) {
    lines = step.state
    let rec = { (line: [String], correct: Bool) in
      MoveResult(mode: .drill, line: line, color: self.color, correct: correct, rated: false, at: Env.now())
    }
    for effect in step.effects {
      switch effect {
      case .record(let line, let correct): store.update { _ = $0.recordMove(tree, rec(line, correct), []) }
      case .buzz(let pattern): Haptics.buzz(pattern.first ?? 0, on: store.state.settings.hapticFeedback)
      case .clearMistake(let id): store.update { $0.clearMistake(id) }
      case .mistake(let mistake): store.update { $0.logMistake(mistake) }
      case .flash:
        Task { [weak self] in
          try? await Task.sleep(for: .milliseconds(500))
          guard let self else { return }
          self.set(L.carryOn(self.lines))
        }
      case .round(let round): store.update { $0.endRound(tree, round) }
      case .gradeLine(let rid, let tip, let grade, let before):
        var from: LineCard?
        store.update { from = $0.gradeLine(rid, tip, grade, before) }
        if before == nil, let from { lines = L.graded(lines, from, grade) }
      }
    }
    settle()
  }
}
