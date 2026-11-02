import ChessCore
import Engine
import Model
import Observation

/// What Growth asks the engine: what it would play past the book
/// (kept in the model's cache), and the eval bar
/// with what each answer on offer does to it.
@MainActor @Observable
final class GrowthEngine {
  static let shared = GrowthEngine()

  /// The eval of a position, and of the moves offered there, centipawns from White's side.
  struct Evals: Equatable {
    var position: Double?
    var moves: [String: Double] = [:]
  }

  /// Bumped as each answer lands, so whatever reads the model's cache redraws.
  private(set) var version = 0
  private var known: [String: Evals] = [:]
  private var positions: [String: Double] = [:]

  @ObservationIgnored private var waiting: [String] = []
  @ObservationIgnored private var asked = Set<String>()
  @ObservationIgnored private var then: [String: [() -> Void]] = [:]
  @ObservationIgnored private var busy = false
  @ObservationIgnored private var evalWaiting: (fen: String, sans: [String])?
  @ObservationIgnored private var evalBusy = false

  private static let depth = 16
  private static let repliesMs: Double = 1500
  private static let evalMs: Double = 1200

  /* ── past the book ── */

  /// Queue positions for the engine, once each; `urgent` goes ahead of the lobby's.
  func ask(_ fens: [String], urgent: Bool = false, then done: (() -> Void)? = nil) {
    for fen in fens {
      let key = positionKey(fen)
      if engineReplies(fen) != nil {
        done?()
        continue
      }
      if let done { then[key, default: []].append(done) }
      if asked.contains(key) {
        if urgent, let at = waiting.firstIndex(where: { positionKey($0) == key }), at > 0 {
          waiting.insert(waiting.remove(at: at), at: 0)
        }
        continue
      }
      asked.insert(key)
      if urgent { waiting.insert(fen, at: 0) } else { waiting.append(fen) }
    }
    pump()
  }

  /// How many of these are still being worked out.
  func pending(_ fens: [String]) -> Int {
    _ = version
    return fens.filter { engineReplies($0) == nil }.count
  }

  private func pump() {
    guard !busy else { return }
    busy = true
    Task {
      while !waiting.isEmpty {
        let fen = waiting.removeFirst()
        if engineReplies(fen) == nil { await work(fen) }
      }
      busy = false
    }
  }

  private func work(_ fen: String) async {
    let snap = await HintEngine.shared.analyse(
      fen, EngineLimits(depth: Self.depth, movetime: Self.repliesMs, multiPv: ENGINE_REPLIES))
    let best = snap.lines.first.flatMap { whiteCp(cp: $0.cp, mate: $0.mate) }
    var sans: [String] = []
    var lost: [Double] = []
    for line in snap.lines {
      guard let uci = line.pv.first, let move = applyUci(fen, uci), !sans.contains(move.san) else { continue }
      sans.append(move.san)
      let cp = whiteCp(cp: line.cp, mate: line.mate)
      lost.append(best == nil || cp == nil ? 0 : max(0, evalLoss(fenTurn(fen), best!, cp!)))
    }
    rememberEngineReplies(fen, sans, lost)
    version += 1
    for done in then.removeValue(forKey: positionKey(fen)) ?? [] { done() }
  }

  /* ── the eval bar ── */

  private static func key(_ fen: String, _ sans: [String]) -> String {
    "\(positionKey(fen))|\(sans.sorted().joined(separator: " "))"
  }

  /// The eval of a position and its moves as far as worked out, asking for the rest.
  func evals(_ fen: String, _ sans: [String]) -> Evals {
    if let full = known[Self.key(fen, sans)] { return full }
    return Evals(position: positions[positionKey(fen)])
  }

  /// Only the position being looked at is worked out: a newer ask replaces one still waiting.
  func askEvals(_ fen: String, _ sans: [String]) {
    guard known[Self.key(fen, sans)] == nil else { return }
    evalWaiting = (fen, sans)
    guard !evalBusy else { return }
    evalBusy = true
    Task {
      while let next = evalWaiting {
        evalWaiting = nil
        if known[Self.key(next.fen, next.sans)] == nil { await evaluate(next.fen, next.sans) }
      }
      evalBusy = false
    }
  }

  private func evaluate(_ fen: String, _ sans: [String]) async {
    let engine = HintEngine.shared
    var position = positions[positionKey(fen)]
    if position == nil {
      let snap = await engine.analyse(fen, EngineLimits(depth: Self.depth, movetime: Self.evalMs, multiPv: 1))
      guard let line = snap.lines.first, let cp = whiteCp(cp: line.cp, mate: line.mate) else { return }
      position = cp
      positions[positionKey(fen)] = cp
    }
    let ucis = sans.compactMap { applySan(fen, $0)?.uci }
    var moves: [String: Double] = [:]
    if !ucis.isEmpty {
      let snap = await engine.analyse(
        fen, EngineLimits(depth: Self.depth, movetime: Self.evalMs, multiPv: ucis.count, searchmoves: ucis))
      for line in snap.lines {
        guard let uci = line.pv.first, let at = ucis.firstIndex(of: uci), let cp = whiteCp(cp: line.cp, mate: line.mate) else { continue }
        moves[sans.filter { applySan(fen, $0) != nil }[at]] = cp
      }
    }
    // The position is worth at least its best move: two searches never agree exactly.
    let white = fenTurn(fen) == .w
    for cp in moves.values { position = white ? max(position!, cp) : min(position!, cp) }
    positions[positionKey(fen)] = position
    known[Self.key(fen, sans)] = Evals(position: position, moves: moves)
  }
}
