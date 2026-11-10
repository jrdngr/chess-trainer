import Book
import ChessCore
import Foundation
import Model
import Observation

/// One sitting of Growth, driven through GrowthController: opened from Home,
/// or grown from the end of an Autopilot or Survival run. Its moves stay in a
/// draft until Save Line. The answers on offer are `HoleAnswers.swift`,
/// the announcement `GrowthModel+Intro.swift`.
@MainActor @Observable
final class GrowthModel {
  /// How a sitting is opened.
  struct Launch {
    var row: GrowthRow
    /// Start standing on this hole rather than the row's.
    var hole: Hole?
    /// The opening grown in: what the round is logged under.
    var opening: OpeningNode
    /// What the run looks for holes with.
    var find: GrowthOptions
    /// What a batch is sized by.
    var maxPly: Int
    /// The selection's opening as the subtitle names it, when not `opening`'s.
    var regionId: String? = nil
    /// A line kept with the sitting's moves from the start: the chosen opening's own.
    var keep: (sans: [String], source: MoveSource)? = nil
    /// The recommendation being filled: the sitting also stops where its named opening ends.
    var gap: Gap? = nil
  }

  enum Intro { case announce, replay, done }

  let launch: Launch
  let index: ReferenceIndex
  let tree: OpeningTree
  let store: AppStore
  /// The tree as it was when the sitting began, with the kept line, so adding cannot re-steer it.
  let start: Repertoire
  /// The sitting's moves, written only by Save Line.
  private(set) var draft: GrowthDraft
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

  /// The sitting has been left: nothing more happens between taps.
  @ObservationIgnored private var left = false
  /// The round Save Line logs.
  @ObservationIgnored private var pending: RoundRecord?
  @ObservationIgnored private var timer: Task<Void, Never>?
  @ObservationIgnored private var timerFor: GrowthSession?
  @ObservationIgnored private var offeredAt: String?
  @ObservationIgnored let tonedMemo = Memo<[NudgedMove]>()

  init?(launch: Launch, store: AppStore, tree: OpeningTree, index: ReferenceIndex) {
    guard let saved = store.state.repertoires[launch.row.repertoireId] else { return nil }
    self.launch = launch
    self.store = store
    self.tree = tree
    self.index = index
    let made = GrowthDraft(saved, keep: launch.keep?.sans, source: launch.keep?.source ?? .picker)
    draft = made
    start = made.rep
    session = beginGrowth(made.rep, launch.row, launch.hole)
    startLength = session.run.path.count
    planIntro()
  }

  /// Grown from the offer at the end of an Autopilot or Survival run, on Growth's own settings.
  convenience init?(offer: GrowOffer, store: AppStore, tree: OpeningTree, index: ReferenceIndex) {
    let prefs = store.state.settings.growth
    let widened = offer.launch.widened
    let find = GrowthOptions(minShare: widened?.minShare ?? prefs.minShare, maxPly: widened?.maxPly ?? prefs.maxPly)
    self.init(
      launch: Launch(
        row: offer.launch.row, hole: offer.launch.hole, opening: offer.launch.opening, find: find, maxPly: prefs.maxPly),
      store: store, tree: tree, index: index)
  }

  /// Filling a recommendation from Home: the sitting starts at its reply, or
  /// at move one for a side's first move. A side with no tree yet gets one.
  convenience init?(gap: Gap, store: AppStore, tree: OpeningTree, index: ReferenceIndex) {
    var gap = gap
    if store.state.repertoires[gap.repertoireId] == nil {
      var repId = ""
      store.update { repId = $0.ensureRepertoire(gap.color) }
      gap.repertoireId = repId
    }
    self.init(
      launch: Launch(
        row: gapRow(gap), hole: gap.hole.san.isEmpty ? nil : gap.hole, opening: deepestNodeWithin(tree, tree.root, gap.line),
        find: GrowthOptions(minShare: GAP_SHARE, maxPly: DEFAULT_MAX_PLY), maxPly: DEFAULT_MAX_PLY, gap: gap),
      store: store, tree: tree, index: index)
  }

  var run: GrowthRun { session.run }
  var phase: GrowthPhase { session.phase }
  /// One fill's size, the same everywhere: the Moves per fill setting.
  var allowance: Int { store.state.settings.movesPerFill }
  var added: Int { inBatch(session) }
  var done: Bool { phase == .done || phase == .lost }
  var fen: String { run.fen }
  var held: Bool { intro != .done }
  var prefs: GrowthPrefs { store.state.settings.growth }
  /// The side's tree as it is now, with this sitting's moves in it.
  var live: Repertoire? { draft.rep }
  /// Answers that X would throw away.
  var unsaved: Int { session.history.count }
  var minShare: Double { launch.find.minShare ?? DEFAULT_MIN_SHARE }
  var nudgePrefs: NudgePrefs { NudgePrefs(priority: prefs.nudgePriority, pawns: prefs.nudgePawns) }
  /// The moves this sitting added, in order.
  var addedSans: [String] { session.added.compactMap { $0 < run.path.count ? run.path[$0] : nil } }

  /* ── taps ── */

  func pick(_ san: String) {
    apply(choose(session, san, allowance, ranked.map(\.san)))
  }

  /// A move on the board: at a hole only the listed answers, on the walk your prep.
  func play(_ move: LegalMove) {
    if phase == .hole {
      if listed.contains(where: { $0.san == move.san }) { pick(move.san) }
      return
    }
    apply(walk(session, start, move.san))
  }

  func undoLast() {
    guard !session.history.isEmpty else { return }
    if session.history.count == 1 { pending = nil }
    apply(undo(session, draft.rep))
  }

  func finish() { update(stop(session)) }

  /// What another batch would answer, once the run has come to rest; nil with nothing left.
  var more: GrowthRun? {
    _ = GrowthEngine.shared.version
    return phase == .done ? resumeAdding(start, index, run) : nil
  }

  func addMore() {
    guard let more else { return }
    apply(anotherBatch(session, start, more))
  }

  /// Save Line: the sitting's moves into the Playbook, and its round logged.
  func save() {
    let id = start.id
    let lines = self.draft
    let round = pending
    store.update { state in
      state.saveGrowth(id, lines)
      if let round { state.endRound(tree, round) }
    }
    pending = nil
  }

  /// Leaving the sitting: nothing more happens between taps. Unsaved moves are dropped.
  func leave() {
    left = true
    timer?.cancel()
  }

  /* ── what happens between taps ── */

  func update(_ next: GrowthSession) {
    guard next != session else { return }
    session = next
    settle()
  }

  /// Keep the controller's step, then do what it asks, in order.
  private func apply(_ step: GrowthStep, settling: Bool = true) {
    session = step.session
    for effect in step.effects {
      switch effect {
      case .addLine(let line): draft.add(line, .each(growthSource(index)))
      case .removeLine(let id): draft.remove(id)
      case .toast(let text): show(text)
      case .edgeFlash: showFlash()
      case .buzz(let ms): Haptics.buzz(ms, on: store.state.settings.hapticFeedback)
      case .log(let kind, let color, let line, let picked, let offered, let all):
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
    guard !left else { return }
    settlePaced()
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
      // A recommendation is filled once its named opening ends or no reply is common enough.
      if phase == .answered, launch.gap != nil, fillEnds(index, run.path, added: added, size: allowance) {
        session = stop(session)
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
    guard phase == .hole, choices(at: run.fen) != nil, offeredAt != run.fen else { return }
    let offered = listed.map(\.san)
    guard !offered.isEmpty else { return }
    offeredAt = run.fen
    log(AppEvent(
      kind: "growth-offer", via: .growth, color: run.color, line: run.path.joined(separator: " "), offered: offered,
      from: run.hole?.kept == true ? "kept" : pastBook ? "engine" : "book"))
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
      try? await Task.sleep(for: .seconds(1.5))
      self?.flash = false
    }
  }
}

extension GrowthModel: HoleAnswers {
  var atHole: Bool { phase == .hole }
  var holeFen: String { run.fen }
  var holePath: [String] { run.path }
  var answerColor: ChessCore.Color { run.color }
  var answerTree: Repertoire? { live }
}
