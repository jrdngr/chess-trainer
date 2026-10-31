import Foundation

/// The backup engine's search: alpha-beta with iterative deepening, a capture
/// search at the leaves, and the usual move ordering. A depth that runs out
/// of time is thrown away, so every line reported comes from one finished
/// depth. `src/engine/basic/search.ts`.

let MATE = 30000
private let MATE_BOUND = MATE - 1000
private let MAX_PLY = 64
private let INF = 32000

public struct RootLine: Sendable {
  public var uci: String
  /// Centipawns for the side to move at the root.
  public var score: Int
  /// Mate in this many moves, positive for the side to move.
  public var mate: Int?
  public var pv: [String]
}

public struct DepthResult: Sendable {
  public var depth: Int
  public var nodes: Int
  public var lines: [RootLine]
}

public struct SearchOptions: Sendable {
  public var maxDepth: Int
  public var timeMs: Double
  public var multiPv: Int
  /// Only these root moves (UCI).
  public var searchmoves: [String]?
  public init(maxDepth: Int, timeMs: Double, multiPv: Int, searchmoves: [String]? = nil) {
    self.maxDepth = maxDepth
    self.timeMs = timeMs
    self.multiPv = multiPv
    self.searchmoves = searchmoves
  }
}

/// Positions already searched, shared by every search of one engine.
final class TranspositionTable {
  static let size = 1 << 19
  var key = [UInt64](repeating: 0, count: size)
  var move = [Int32](repeating: 0, count: size)
  var score = [Int16](repeating: 0, count: size)
  var depth = [Int8](repeating: 0, count: size)
  /// 0 empty, then exact, a lower bound or an upper bound.
  var flag = [UInt8](repeating: 0, count: size)
}

private let EXACT: UInt8 = 1, LOWER: UInt8 = 2, UPPER: UInt8 = 3

private func toTT(_ score: Int, _ ply: Int) -> Int { score > MATE_BOUND ? score + ply : score < -MATE_BOUND ? score - ply : score }
private func fromTT(_ score: Int, _ ply: Int) -> Int { score > MATE_BOUND ? score - ply : score < -MATE_BOUND ? score + ply : score }

private func mateIn(_ score: Int) -> Int? {
  if score > MATE_BOUND { return Int((Double(MATE - score) / 2).rounded(.up)) }
  if score < -MATE_BOUND { return -Int((Double(MATE + score) / 2).rounded(.up)) }
  return nil
}

private struct OutOfTime: Error {}

/// The deepest finished search of a position, or nil when it has no legal moves.
/// `onDepth` is told after each finished depth; `stopped` is asked as it goes.
func search(_ fen: String, _ options: SearchOptions, _ tt: TranspositionTable, onDepth: ((DepthResult) -> Void)? = nil, stopped: @escaping () -> Bool = { false }) -> DepthResult? {
  Searcher(Position(fen), options, tt, onDepth, stopped).run()
}

private final class Searcher {
  private var nodes = 0
  private let deadline: Double
  private var killers = [[Int]](repeating: [0, 0], count: MAX_PLY)
  private var history = [Int](repeating: 0, count: 128 * 128)
  private var pvTable = [[Int]](repeating: [Int](repeating: 0, count: MAX_PLY), count: MAX_PLY)
  private var pvLength = [Int](repeating: 0, count: MAX_PLY)
  private var previousPv: [Int] = []
  private var followPv = false
  private var timed = false
  private let pos: Position
  private let options: SearchOptions
  private let tt: TranspositionTable
  private let onDepth: ((DepthResult) -> Void)?
  private let stopped: () -> Bool

  init(_ pos: Position, _ options: SearchOptions, _ tt: TranspositionTable, _ onDepth: ((DepthResult) -> Void)?, _ stopped: @escaping () -> Bool) {
    self.pos = pos
    self.options = options
    self.tt = tt
    self.onDepth = onDepth
    self.stopped = stopped
    deadline = Date().timeIntervalSince1970 * 1000 + options.timeMs
  }

  private func now() -> Double { Date().timeIntervalSince1970 * 1000 }

  func run() -> DepthResult? {
    let only = options.searchmoves.flatMap { $0.isEmpty ? nil : Set($0) }
    var roots = pos.legalMoves().filter { only == nil || only!.contains(moveToUci($0)) }
    if roots.isEmpty { return nil }
    let multiPv = max(1, min(options.multiPv, roots.count))
    let start = now()
    var best: DepthResult?
    var pvs: [Int: [Int]] = [:]
    let maxDepth = max(1, min(options.maxDepth, MAX_PLY - 8))
    for depth in 1...maxDepth {
      // The first depth always finishes, so there is an answer however tight the time.
      timed = depth > 1
      var scored: [(move: Int, score: Int, exact: Bool, pv: [Int])] = []
      do {
        for move in roots {
          let exact = scored.filter(\.exact).map(\.score).sorted(by: >)
          let floor = exact.count >= multiPv ? exact[multiPv - 1] : -INF
          previousPv = pvs[move] ?? []
          followPv = previousPv.count > 1
          _ = pos.make(move)
          var score: Int
          do {
            if floor == -INF {
              score = -(try negamax(depth - 1, -INF, INF, 1, true))
            } else {
              // Only worth an exact score if it might make the top lines.
              score = -(try negamax(depth - 1, -floor - 1, -floor, 1, true))
              if score > floor { score = -(try negamax(depth - 1, -INF, -floor, 1, true)) }
            }
          } catch {
            pos.unmake(move)
            throw error
          }
          pos.unmake(move)
          let pv = [move] + Array(pvTable[1][1..<max(1, pvLength[1])])
          scored.append((move, score, score > floor, pv))
        }
      } catch {
        break
      }
      scored = scored.enumerated().sorted { a, b in
        if a.element.exact == b.element.exact {
          return a.element.score != b.element.score ? a.element.score > b.element.score : a.offset < b.offset
        }
        return a.element.exact
      }.map(\.element)
      roots = scored.map(\.move)
      pvs = Dictionary(scored.map { ($0.move, $0.pv) }, uniquingKeysWith: { a, _ in a })
      let result = DepthResult(depth: depth, nodes: nodes, lines: scored.prefix(multiPv).map {
        RootLine(uci: moveToUci($0.move), score: $0.score, mate: mateIn($0.score), pv: $0.pv.map(moveToUci))
      })
      best = result
      onDepth?(result)
      if abs(result.lines[0].score) > MATE_BOUND && depth >= 4 { break }
      // The next depth costs several times this one: not worth starting if it cannot finish.
      if now() - start > options.timeMs * 0.45 || stopped() { break }
    }
    return best
  }

  private func tick() throws {
    nodes += 1
    if nodes & 1023 == 0 && timed && (now() > deadline || stopped()) { throw OutOfTime() }
  }

  private func negamax(_ depthIn: Int, _ alphaIn: Int, _ beta: Int, _ ply: Int, _ allowNull: Bool) throws -> Int {
    try tick()
    pvLength[ply] = ply
    var depth = depthIn, alpha = alphaIn
    if pos.halfmove >= 100 || pos.repeated() || insufficientMaterial(pos) { return 0 }
    if ply >= MAX_PLY - 1 { return evaluate(pos) }
    let inCheck = pos.inCheck()
    if inCheck { depth += 1 }
    if depth <= 0 { return try quiesce(alpha, beta, ply) }

    let slot = Int(pos.key & UInt64(TranspositionTable.size - 1))
    let hit = tt.flag[slot] != 0 && tt.key[slot] == pos.key
    let hashMove = hit ? Int(tt.move[slot]) : 0
    // Only off the main line: taking a stored score there would cut its variation short.
    if hit && beta - alpha == 1 && Int(tt.depth[slot]) >= depth {
      let stored = fromTT(Int(tt.score[slot]), ply)
      let flag = tt.flag[slot]
      if flag == EXACT || (flag == LOWER && stored >= beta) || (flag == UPPER && stored <= alpha) { return stored }
    }
    let alphaAtStart = alpha

    if allowNull && !inCheck && depth >= 3 && beta < MATE_BOUND && pos.hasPieces(pos.side) && evaluate(pos) >= beta {
      pos.makeNull()
      let score: Int
      do { score = -(try negamax(depth - 3, -beta, -beta + 1, ply + 1, false)) } catch {
        pos.unmakeNull()
        throw error
      }
      pos.unmakeNull()
      if score >= beta { return score }
    }

    let moves = order(pos.pseudoMoves(), ply, hashMove)
    var legal = 0, best = -INF, bestMove = 0
    for move in moves {
      if !pos.make(move) { continue }
      legal += 1
      let quiet = flagsOf(move) & CAPTURE == 0 && promoOf(move) == 0
      var score: Int
      do {
        if legal == 1 {
          score = -(try negamax(depth - 1, -beta, -alpha, ply + 1, true))
        } else {
          // Late quiet moves rarely matter: look at them a little shallower first.
          let reduce = depth >= 3 && legal > 4 && quiet && !inCheck && !pos.inCheck() ? 1 : 0
          score = -(try negamax(depth - 1 - reduce, -alpha - 1, -alpha, ply + 1, true))
          if score > alpha && (reduce > 0 || score < beta) { score = -(try negamax(depth - 1, -beta, -alpha, ply + 1, true)) }
        }
      } catch {
        pos.unmake(move)
        throw error
      }
      pos.unmake(move)
      if score > best {
        best = score
        bestMove = move
      }
      if score > alpha {
        alpha = score
        pvTable[ply][ply] = move
        var i = ply + 1
        while i < pvLength[ply + 1] {
          pvTable[ply][i] = pvTable[ply + 1][i]
          i += 1
        }
        pvLength[ply] = max(ply + 1, pvLength[ply + 1])
        if score >= beta {
          if quiet {
            if killers[ply][0] != move {
              killers[ply][1] = killers[ply][0]
              killers[ply][0] = move
            }
            history[fromOf(move) * 128 + toOf(move)] += depth * depth
          }
          store(slot, depth, score, LOWER, move, ply)
          return score
        }
      }
    }
    if legal == 0 { return inCheck ? -MATE + ply : 0 }
    store(slot, depth, best, best > alphaAtStart ? EXACT : UPPER, bestMove, ply)
    return best
  }

  private func store(_ slot: Int, _ depth: Int, _ score: Int, _ flag: UInt8, _ move: Int, _ ply: Int) {
    // Keep a deeper result for the same position over a shallower one.
    if tt.flag[slot] != 0 && tt.key[slot] == pos.key && Int(tt.depth[slot]) > depth { return }
    tt.key[slot] = pos.key
    tt.move[slot] = Int32(move)
    tt.score[slot] = Int16(clamping: toTT(score, ply))
    tt.depth[slot] = Int8(clamping: min(depth, 127))
    tt.flag[slot] = flag
  }

  private func quiesce(_ alphaIn: Int, _ beta: Int, _ ply: Int) throws -> Int {
    try tick()
    pvLength[ply] = ply
    var alpha = alphaIn
    let stand = evaluate(pos)
    if stand >= beta || ply >= MAX_PLY - 1 { return stand }
    if stand > alpha { alpha = stand }
    var best = stand
    for move in orderCaptures(pos.pseudoMoves(true)) {
      // Even winning the piece outright would not get back to alpha.
      let gain = PIECE_VALUE[pos.sq[toOf(move)] & 7] + (promoOf(move) != 0 ? 800 : 0)
      if stand + gain + 200 < alpha && promoOf(move) == 0 { continue }
      if !pos.make(move) { continue }
      let score: Int
      do { score = -(try quiesce(-beta, -alpha, ply + 1)) } catch {
        pos.unmake(move)
        throw error
      }
      pos.unmake(move)
      if score > best { best = score }
      if score > alpha {
        alpha = score
        if score >= beta { return score }
      }
    }
    return best
  }

  /// Most valuable victim first, then least valuable attacker.
  private func captureScore(_ move: Int) -> Double {
    let victimType = pos.sq[toOf(move)] & 7
    let victim = flagsOf(move) & CAPTURE != 0 ? (victimType != 0 ? PIECE_VALUE[victimType] : PIECE_VALUE[1]) : 0
    let attacker = PIECE_VALUE[pos.sq[fromOf(move)] & 7]
    return Double(victim * 10) - Double(attacker) / 100 + (promoOf(move) != 0 ? Double(PIECE_VALUE[promoOf(move)] * 10) : 0)
  }

  private func orderCaptures(_ moves: [Int]) -> [Int] {
    moves.map { ($0, captureScore($0)) }.enumerated().sorted { a, b in
      a.element.1 != b.element.1 ? a.element.1 > b.element.1 : a.offset < b.offset
    }.map(\.element.0)
  }

  private func order(_ moves: [Int], _ ply: Int, _ hashMove: Int) -> [Int] {
    var pvMove = 0
    if followPv {
      followPv = false
      if ply < previousPv.count, moves.contains(previousPv[ply]) {
        pvMove = previousPv[ply]
        followPv = true
      }
    }
    let k0 = killers[ply][0], k1 = killers[ply][1]
    return moves.map { m -> (Int, Double) in
      let k: Double
      if m == pvMove { k = 2e9 } else if m == hashMove { k = 1e9 } else if flagsOf(m) & CAPTURE != 0 || promoOf(m) != 0 { k = 1e8 + captureScore(m) } else if m == k0 { k = 9e7 } else if m == k1 { k = 8e7 } else {
        k = Double(history[fromOf(m) * 128 + toOf(m)])
      }
      return (m, k)
    }.enumerated().sorted { a, b in
      a.element.1 != b.element.1 ? a.element.1 > b.element.1 : a.offset < b.offset
    }.map(\.element.0)
  }
}
