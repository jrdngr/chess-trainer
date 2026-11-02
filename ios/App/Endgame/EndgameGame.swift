import ChessCore
import Engine
import Foundation
import Model
import Observation

/// One round of Endgame mode: a position from the library played out against
/// the engine. Each move of yours is judged by the result it keeps; a slip
/// ends the round, and so does meeting the goal.
@MainActor @Observable
final class EndgameGame {
  enum Phase { case intro, playing, over }

  let entry: EndgameEntry
  let color: ChessCore.Color
  let start: String
  /// One id for the life of the round, so it is recorded once.
  let roundId = UUID()

  private(set) var fen: String
  private(set) var moves: [String] = []
  private(set) var yourMoves = 0
  private(set) var thinking = false
  private(set) var phase: Phase
  private(set) var outcome: EndgameOutcome?
  /// The engine's last word on the position, White's side.
  private(set) var evalCp: Double?
  /// "Missed mate", for a beat over the board.
  private(set) var note: String?
  /// The engine's move where you missed a mate.
  private(set) var missedBest: (from: String, to: String)?

  @ObservationIgnored private let store: AppStore
  @ObservationIgnored private let engine = BasicEngine()
  @ObservationIgnored private let judgeEngine = BasicEngine()
  @ObservationIgnored private var task: Task<Void, Never>?
  @ObservationIgnored private var promoted = false

  /// How long the engine thinks over its own move.
  static let thinkMs: Double = 900

  init(entry: EndgameEntry, store: AppStore) {
    self.entry = entry
    self.store = store
    start = endgameStart(entry, Env.random)
    fen = start
    color = fenTurn(start)
    phase = entry.intro != nil && !store.state.endgames.seenIntros.contains(entry.id) ? .intro : .playing
  }

  var myTurn: Bool { phase == .playing && fenTurn(fen) == color && !thinking }
  var lastMove: (from: String, to: String)? { lastMoveOf(moves, start) }

  /// The intro card is read: on to the board.
  func toBoard() {
    guard phase == .intro else { return }
    store.update { $0.endgames.sawIntro(entry.id) }
    phase = .playing
  }

  /// Show the intro card again.
  func replayIntro() {
    guard entry.intro != nil, phase == .playing, moves.isEmpty else { return }
    phase = .intro
  }

  func stop() { task?.cancel() }

  func play(_ move: LegalMove) {
    guard myTurn else { return }
    let before = fen
    note = nil
    missedBest = nil
    moves.append(move.san)
    fen = move.after
    yourMoves += 1
    if move.promotion != nil { promoted = true }
    thinking = true
    Haptics.buzz(10, on: store.state.settings.hapticFeedback)
    task = Task { [weak self, judgeEngine, color] in
      let base = await baseline(judgeEngine, before, moments: false)
      var judged: Judgement? = nil
      if let base { judged = await judge(judgeEngine, base, san: move.san, uci: move.uci, color: color, moments: false) }
      guard let self, !Task.isCancelled else { return }
      self.settle(move, before, judged)
    }
  }

  /// Give the round up: it counts as a miss.
  func resign() {
    guard phase == .playing else { return }
    end(.failure(text: "Resigned"))
  }

  private func settle(_ move: LegalMove, _ before: String, _ judged: Judgement?) {
    thinking = false
    if let judged {
      evalCp = judged.after
      if !judged.ok {
        let slip = judged.exact ?? ResultSlip(from: resultOf(color, judged.before), to: resultOf(color, judged.after))
        end(.failure(text: slipText(slip.from, slip.to) ?? "Gave it away"))
        return
      }
      if judged.missedMate {
        note = "Missed mate"
        missedBest = judged.best.flatMap { applySan(before, $0) }.map { ($0.from, $0.to) }
      }
    }
    let won = exactResult(fen, for: color) ?? judged.map { resultOf(color, $0.after) }
    if let done = endgameOutcome(entry, fen, you: color, yourMoves: yourMoves, promoted: promoted, stillWon: won == .win) {
      end(done)
      return
    }
    engineTurn()
  }

  /// Their move: the tablebase's best where it knows, the engine's otherwise.
  func engineTurn() {
    guard phase == .playing, outcome == nil, fenTurn(fen) != color else { return }
    let fen = fen
    let them = color.other
    thinking = true
    task = Task { [weak self, engine] in
      var choices: [String]? = nil
      let legal = legalMoves(fen)
      let known = legal.map { ($0.uci, exactResult($0.after, for: them)) }
      if known.allSatisfy({ $0.1 != nil }), let best = known.compactMap(\.1).max() {
        choices = known.filter { $0.1 == best }.map(\.0)
      }
      let snap = await engine.analyse(fen, EngineLimits(depth: 14, movetime: Self.thinkMs, multiPv: 1, searchmoves: choices))
      let uci = snap.lines.first?.pv.first ?? choices?.first ?? legal.first?.uci
      guard let self, !Task.isCancelled, self.fen == fen else { return }
      self.thinking = false
      guard let uci, let move = applyUci(fen, uci) else { return }
      self.moves.append(move.san)
      self.fen = move.after
      if let done = endgameOutcome(
        self.entry, self.fen, you: self.color, yourMoves: self.yourMoves, promoted: self.promoted, stillWon: false)
      {
        self.end(done)
      }
    }
  }

  private func end(_ result: EndgameOutcome) {
    task?.cancel()
    thinking = false
    outcome = result
    phase = .over
    let success: Bool, mission: Bool
    switch result {
    case .success(_, let m): (success, mission) = (true, m)
    case .failure: (success, mission) = (false, false)
    }
    store.update { $0.endgames.review(entry, success: success, mission: mission, now: Env.now()) }
  }
}
