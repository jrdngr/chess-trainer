import Book
import ChessCore
import Foundation
import Model
import Observation

/// One sitting of Growth, driven through GrowthController. Autopilot's batch, grown from the end of a run, and
/// Growth opened from Home are both one of these; `Launch.paced` is the
/// difference. The answers on offer are `GrowthModel+Answers.swift`, the
/// announcement `GrowthModel+Intro.swift`.
@MainActor @Observable
final class GrowthModel {
  /// How a sitting is opened.
  struct Launch {
    var row: GrowthRow
    /// Start standing on this hole rather than the row's.
    var hole: Hole?
    /// The opening grown in: what the round is logged under, and the card and New run read.
    var opening: OpeningNode
    /// What the run looks for holes with.
    var find: GrowthOptions
    /// What a batch is sized by.
    var maxPly: Int
    /// Growth from Home: announced, paced like a game, and its events logged.
    /// Off, Autopilot's batch settles at once and logs its round at rest.
    var paced: Bool
    /// The selection's opening as the subtitle names it, when not `opening`'s: "Any favorite".
    var regionId: String? = nil
  }

  enum Intro { case announce, replay, done }

  let launch: Launch
  let index: ReferenceIndex
  let tree: OpeningTree
  let store: AppStore
  /// The tree as it was when the sitting began, so adding cannot re-steer it.
  let start: Repertoire
  private(set) var session: GrowthSession
  /// The opponent is about to move.
  private(set) var thinking = false
  /// "End of the book", flashed over the board.
  private(set) var flash = false
  /// Autopilot's own toast, over the board; Growth's go to `onToast`.
  private(set) var toast: String?
  @ObservationIgnored var onToast: ((String) -> Void)?

  var intro = Intro.done
  var introPly = 0
  /// The moves the announcement plays out, and the opening it names.
  @ObservationIgnored var introPath: [String] = []
  @ObservationIgnored var introOpening = ""
  @ObservationIgnored var introName: String?
  /// The path's length when the run began: a longer one means you have moved.
  @ObservationIgnored var startLength = 0

  @ObservationIgnored private var logged = false
  /// The round this sitting will log on the way out (paced).
  @ObservationIgnored private var pending: RoundRecord?
  @ObservationIgnored private var timer: Task<Void, Never>?
  @ObservationIgnored private var timerFor: GrowthSession?
  @ObservationIgnored private var offeredAt: String?
  @ObservationIgnored let tonedMemo = Memo<[NudgedMove]>()

  init?(launch: Launch, store: AppStore, tree: OpeningTree, index: ReferenceIndex) {
    guard let rep = store.state.repertoires[launch.row.repertoireId] else { return nil }
    self.launch = launch
    self.store = store
    self.tree = tree
    self.index = index
    start = rep
    session = beginGrowth(rep, launch.row, launch.hole)
    startLength = session.run.path.count
    if launch.paced { planIntro() } else { settle() }
  }

  /// Autopilot's batch, from the offer at the end of a run.
  convenience init?(offer: GrowOffer, store: AppStore, tree: OpeningTree, index: ReferenceIndex) {
    let widened = offer.launch.widened
    let find = GrowthOptions(minShare: widened?.minShare ?? AUTO_GROWTH.minShare, maxPly: widened?.maxPly ?? AUTO_GROWTH.maxPly)
    self.init(
      launch: Launch(
        row: offer.launch.row, hole: offer.launch.hole, opening: offer.launch.opening, find: find,
        maxPly: find.maxPly ?? AUTO_GROWTH.maxPly, paced: false),
      store: store, tree: tree, index: index)
  }

  var run: GrowthRun { session.run }
  var phase: GrowthPhase { session.phase }
  var allowance: Int { allowanceOf(session, launch.maxPly) }
  var added: Int { inBatch(session) }
  var done: Bool { phase == .done || phase == .lost }
  var fen: String { launch.paced ? run.fen : session.answer?.after ?? run.fen }
  var held: Bool { intro != .done }
  /// Growth's own settings; Autopilot's batch grows on its fixed ones.
  var prefs: GrowthPrefs { launch.paced ? store.state.settings.growth : AUTO_GROWTH }
  /// The side's tree as it is now, with this sitting's moves in it.
  var live: Repertoire? { store.state.repertoires[start.id] }
  var minShare: Double { launch.find.minShare ?? DEFAULT_MIN_SHARE }
  /// The moves this sitting added, in order.
  var addedSans: [String] { session.added.compactMap { $0 < run.path.count ? run.path[$0] : nil } }

  /* ── taps ── */

  func pick(_ san: String) {
    apply(choose(session, san, allowance, launch.paced ? ranked.map(\.san) : choices.map(\.san)))
  }

  /// A move on the board: at a hole only the listed answers, on the walk your prep.
  func play(_ move: LegalMove) {
    if phase == .hole {
      if listed.contains(where: { $0.san == move.san }) { pick(move.san) }
      return
    }
    apply(walk(session, start, move.san))
  }

  func undoLast() { takeBack(all: false) }
  func undoAll() { takeBack(all: true) }

  private func takeBack(all: Bool) {
    guard !session.history.isEmpty else { return }
    if all || session.history.count == 1 { pending = nil }
    apply(undo(session, live, all: all))
  }

  func finish() {
    update(stop(session))
    if !launch.paced { logRound() }
  }

  /// What another batch would answer, once the run has come to rest; nil with nothing left.
  var more: GrowthRun? {
    _ = GrowthEngine.shared.version
    return phase == .done ? resumeAdding(start, index, run) : nil
  }

  func addMore() {
    guard let more else { return }
    apply(anotherBatch(session, start, more))
  }

  /// Leaving the sitting: the round is logged on the way out.
  func leave() {
    timer?.cancel()
    if launch.paced, let pending { store.update { $0.endRound(tree, pending) } }
    pending = nil
  }

  func clearFlash() { flash = false }

  /* ── what happens between taps ── */

  func update(_ next: GrowthSession) {
    guard next != session else { return }
    session = next
    settle()
  }

  /// Keep the controller's step, then do what it asks, in order.
  private func apply(_ step: GrowthStep, settling: Bool = true) {
    session = step.session
    let rid = start.id
    for effect in step.effects {
      switch effect {
      case .addLine(let line): store.update { $0.addGrowthLine(rid, line, index) }
      case .removeLine(let id):
        if launch.paced { store.update { $0.removeNode(rid, id, via: .growth) } } else { store.update { $0.removeLine(rid, id) } }
      case .toast(let text): show(text)
      case .edgeFlash:
        if launch.paced { showFlash() } else { show("End of the book") }
      case .buzz(let ms): Haptics.buzz(ms, on: store.state.settings.hapticFeedback)
      case .log(let kind, let color, let line, let picked, let offered, let all):
        guard launch.paced else { break }
        let undo = kind == "growth-undo"
        log(AppEvent(
          kind: kind, via: .growth, color: color, line: line, picked: undo ? nil : picked, offered: undo ? nil : offered,
          all: undo ? all : nil))
      }
    }
    if settling { settle() }
  }

  func log(_ event: AppEvent) { store.update { $0.logEvent(event) } }

  func settle() {
    if launch.paced { settlePaced() } else { settleNow() }
  }

  /// Autopilot's batch: everything between taps happens at once.
  private func settleNow() {
    for _ in 0..<200 {
      let before = session
      if session.phase == .walking {
        session = opponentToMove(session, start)
          ? opponentWalks(session, start, index, launch.find)
          : nothingPrepared(session, preparedHere(start, session.run).count)
      }
      if (session.phase == .hole || session.phase == .answered) && pastTheBook(index, session.run.fen) {
        apply(reachedEdge(session), settling: false)
      }
      if session.phase == .hole {
        session = choices.isEmpty ? stop(session) : measureBatch(session, launch.maxPly)
      }
      if session.phase == .answered, let hole = nextHole(index, session.run) {
        session = theyReply(session, hole)
      }
      if session == before { break }
    }
    if done { logRound() }
  }

  /// Growth's sitting: the opponent answers after a beat, and the engine is waited for.
  private func settlePaced() {
    guard !held else { return }
    for _ in 0..<50 {
      let before = session
      if phase == .walking && !opponentToMove(session, start) {
        session = nothingPrepared(session, preparedHere(start, run).count)
      }
      if (phase == .hole || phase == .answered) && !prefs.pastBook && pastTheBook(index, run.fen) {
        apply(reachedEdge(session), settling: false)
      }
      if phase == .hole {
        if let offered = choicesAt(index, run.fen, 4), offered.isEmpty { session = stop(session) }
        session = measureBatch(session, launch.maxPly)
      }
      if session == before { break }
    }
    if (phase == .hole || phase == .answered) && needsEngine(index, run.fen) {
      GrowthEngine.shared.ask([run.fen], urgent: true) { [weak self] in self?.settle() }
    }
    if timerFor != session {
      timer?.cancel()
      timer = nil
      timerFor = nil
      thinking = false
      if opponentToMove(session, start) {
        thinking = true
        after(420) { $0.thinking = false; $0.update(opponentWalks($0.session, $0.start, $0.index, $0.launch.find)) }
      } else if phase == .answered, let hole = nextHole(index, run) {
        after(520) { $0.update(theyReply($0.session, hole)) }
      }
    }
    logOffer()
    if let round = growthRound(session, tree, launch.opening, allowance, at: Env.now()) { pending = round }
  }

  private func after(_ ms: Int, _ then: @escaping (GrowthModel) -> Void) {
    timerFor = session
    timer = Task { [weak self] in
      try? await Task.sleep(for: .milliseconds(ms))
      guard !Task.isCancelled, let self else { return }
      self.timer = nil
      self.timerFor = nil
      then(self)
    }
  }

  /// What each hole put in front of you, logged once per position when its moves are in.
  func logOffer() {
    guard launch.paced, phase == .hole, choices(at: run.fen) != nil, offeredAt != run.fen else { return }
    let offered = listed.map(\.san)
    guard !offered.isEmpty else { return }
    offeredAt = run.fen
    log(AppEvent(
      kind: "growth-offer", via: .growth, color: run.color, line: run.path.joined(separator: " "), offered: offered,
      from: run.hole?.kept == true ? "kept" : pastBook ? "engine" : "book"))
  }

  /// One sitting is one round, logged once it is at rest (Autopilot).
  private func logRound() {
    guard !logged, let round = growthRound(session, tree, launch.opening, allowance, at: Env.now()) else { return }
    logged = true
    store.update { $0.endRound(tree, round) }
  }

  private func show(_ text: String) {
    if let onToast { return onToast(text) }
    toast = text
    Task { @MainActor [weak self] in
      try? await Task.sleep(for: .seconds(1.6))
      if self?.toast == text { self?.toast = nil }
    }
  }

  private func showFlash() {
    flash = true
    Task { @MainActor [weak self] in
      try? await Task.sleep(for: .seconds(2))
      self?.flash = false
    }
  }
}
