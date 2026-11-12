import Book
import ChessCore
import Foundation
import Model
import Observation

/// One sitting of Growth, driven through GrowthController: opened from Home,
/// or grown from the end of a Play run or a run you set up. Its moves stay in a
/// draft until Save Line. The answers on offer are `HoleAnswers.swift`,
/// the announcement `GrowthModel+Intro.swift`.
@MainActor @Observable
public final class GrowthModel {
  /// How a sitting is opened.
  public struct Launch {
    public var row: GrowthRow
    /// Start standing on this hole rather than the row's.
    public var hole: Hole?
    /// The opening grown in: what the round is logged under.
    public var opening: OpeningNode
    /// What the run looks for holes with.
    public var find: GrowthOptions
    /// What a batch is sized by.
    public var maxPly: Int
    /// The selection's opening as the subtitle names it, when not `opening`'s.
    public var regionId: String? = nil
    /// A line kept with the sitting's moves from the start: the chosen opening's own.
    public var keep: (sans: [String], source: MoveSource)? = nil
    /// The recommendation being filled: the sitting also stops where its named opening ends.
    public var gap: Gap? = nil
  }

  public enum Intro { case announce, replay, done }

  public let launch: Launch
  public let index: ReferenceIndex
  public let tree: OpeningTree
  public let store: AppStore
  /// The tree as it was when the sitting began, with the kept line, so adding cannot re-steer it.
  public let start: Playbook
  /// The sitting's moves, written only by Save Line.
  public private(set) var draft: GrowthDraft
  public private(set) var session: GrowthSession
  /// The opponent is about to move.
  public private(set) var thinking = false
  /// "End of the book", flashed over the board.
  public private(set) var flash = false
  /// Play's own toast, over the board; Growth's go to `onToast`.
  public private(set) var toast: String?
  @ObservationIgnored public var onToast: ((String) -> Void)?

  public var intro = Intro.done
  public var introPly = 0
  /// The moves the announcement plays out, and the opening it names.
  @ObservationIgnored public var introPath: [String] = []
  @ObservationIgnored public var introOpening = ""
  @ObservationIgnored public var introName: String?
  /// The path's length when the run began: a longer one means you have moved.
  @ObservationIgnored public var startLength = 0

  /// The sitting has been left: nothing more happens between taps.
  @ObservationIgnored private var left = false
  /// The round Save Line logs.
  @ObservationIgnored private var pending: RoundRecord?
  @ObservationIgnored private var timer: Task<Void, Never>?
  @ObservationIgnored private var timerFor: GrowthSession?
  @ObservationIgnored private var offeredAt: String?
  @ObservationIgnored public let tonedMemo = Memo<[NudgedMove]>()

  public init?(launch: Launch, store: AppStore, tree: OpeningTree, index: ReferenceIndex) {
    guard let saved = store.state.playbooks[launch.row.playbookId] else { return nil }
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

  /// Grown from the offer at the end of a Play run or a run you set up, on Growth's own settings.
  public convenience init?(offer: GrowOffer, store: AppStore, tree: OpeningTree, index: ReferenceIndex) {
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
  public convenience init?(gap: Gap, store: AppStore, tree: OpeningTree, index: ReferenceIndex) {
    var gap = gap
    if store.state.playbooks[gap.playbookId] == nil {
      var repId = ""
      store.update { repId = $0.ensurePlaybook(gap.color) }
      gap.playbookId = repId
    }
    self.init(
      launch: Launch(
        row: gapRow(gap), hole: gap.hole.san.isEmpty ? nil : gap.hole, opening: deepestNodeWithin(tree, tree.root, gap.line),
        find: GrowthOptions(minShare: GAP_SHARE, maxPly: DEFAULT_MAX_PLY), maxPly: DEFAULT_MAX_PLY, gap: gap),
      store: store, tree: tree, index: index)
  }

  public var services: GameServices { store.services }
  public var run: GrowthRun { session.run }
  public var phase: GrowthPhase { session.phase }
  /// One fill's size, the same everywhere: the New moves per round setting.
  public var allowance: Int { store.state.settings.movesPerFill }
  public var added: Int { inBatch(session) }
  public var done: Bool { phase == .done || phase == .lost }
  public var fen: String { run.fen }
  public var held: Bool { intro != .done }
  public var prefs: GrowthPrefs { store.state.settings.growth }
  /// The side's tree as it is now, with this sitting's moves in it.
  public var live: Playbook? { draft.rep }
  /// Answers that X would throw away.
  public var unsaved: Int { session.history.count }
  public var minShare: Double { launch.find.minShare ?? DEFAULT_MIN_SHARE }
  public var nudgePrefs: NudgePrefs { NudgePrefs(priority: prefs.nudgePriority, pawns: prefs.nudgePawns) }
  /// The moves this sitting added, in order.
  public var addedSans: [String] { session.added.compactMap { $0 < run.path.count ? run.path[$0] : nil } }

  /* ── taps ── */

  public func pick(_ san: String) {
    apply(choose(session, san, allowance, ranked.map(\.san)))
  }

  /// A move on the board: at a hole only the listed answers, on the walk your prep.
  public func play(_ move: LegalMove) {
    if phase == .hole {
      if listed.contains(where: { $0.san == move.san }) { pick(move.san) }
      return
    }
    apply(walk(session, start, move.san))
  }

  public func undoLast() {
    guard !session.history.isEmpty else { return }
    if session.history.count == 1 { pending = nil }
    apply(undo(session, draft.rep))
  }

  public func finish() { update(stop(session)) }

  /// What another batch would answer, once the run has come to rest; nil with nothing left.
  public var more: GrowthRun? {
    phase == .done ? resumeAdding(start, index, run) : nil
  }

  public func addMore() {
    guard let more else { return }
    apply(anotherBatch(session, start, more))
  }

  /// Save Line: the sitting's moves into the Playbook, and its round logged.
  public func save() {
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
  public func leave() {
    left = true
    timer?.cancel()
  }

  /* ── what happens between taps ── */

  public func update(_ next: GrowthSession) {
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
      case .buzz(let ms): services.emit(.buzz(ms))
      case .log(let kind, let color, let line, let picked, let offered, let all):
        let undo = kind == "growth-undo"
        log(AppEvent(
          kind: kind, via: .growth, color: color, line: line, picked: undo ? nil : picked, offered: undo ? nil : offered,
          all: undo ? all : nil))
      }
    }
    if settling { settle() }
  }

  public func log(_ event: AppEvent) { store.update { $0.logEvent(event) } }

  public func settle() {
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
      if (phase == .hole || phase == .answered) && pastTheBook(index, run.fen) {
        apply(reachedEdge(session), settling: false)
      }
      // A recommendation is filled once its named opening ends or no reply is common enough.
      if phase == .answered, launch.gap != nil, fillEnds(index, run.path, added: added, size: allowance) {
        session = stop(session)
      }
      if phase == .hole {
        if choicesAt(index, run.fen, 4).isEmpty { session = stop(session) }
        session = measureBatch(session, launch.maxPly)
      }
      if session == before { break }
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
    let clock = services.clock
    timer = services.spawn { [weak self] in
      await clock.sleep(Double(ms) / 1000)
      guard !Task.isCancelled, let self else { return }
      self.timer = nil
      self.timerFor = nil
      then(self)
    }
  }

  /// What each hole put in front of you, logged once per position when its moves are in.
  public func logOffer() {
    guard phase == .hole, offeredAt != run.fen else { return }
    let offered = listed.map(\.san)
    guard !offered.isEmpty else { return }
    offeredAt = run.fen
    log(AppEvent(
      kind: "growth-offer", via: .growth, color: run.color, line: run.path.joined(separator: " "), offered: offered,
      from: run.hole?.kept == true ? "kept" : "book"))
  }

  private func show(_ text: String) {
    services.emit(.toast(text))
    if let onToast { return onToast(text) }
    toast = text
    let clock = services.clock
    services.spawn { [weak self] in
      await clock.sleep(1.6)
      if self?.toast == text { self?.toast = nil }
    }
  }

  private func showFlash() {
    flash = true
    services.emit(.edgeFlash)
    let clock = services.clock
    services.spawn { [weak self] in
      await clock.sleep(1.5)
      self?.flash = false
    }
  }
}

extension GrowthModel: HoleAnswers {
  public var atHole: Bool { phase == .hole }
  public var holeFen: String { run.fen }
  public var holePath: [String] { run.path }
  public var answerColor: ChessCore.Color { run.color }
  public var answerTree: Playbook? { live }
}
