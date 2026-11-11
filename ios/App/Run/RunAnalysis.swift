import ChessCore
import Engine
import Model
import Observation

/// A finished run, analysed on its own board: the game's moves to step back and forth
/// through, moves played on the board to try others, and the engine's eval and top move from each position.
/// Past the game's end, stepping forward plays the top move.
@MainActor @Observable
final class RunAnalysis {
  /// The game as played, its last move the one that ended it.
  let game: [String]
  /// The line being looked at: the game, or another tried from a position in it.
  private(set) var line: [String]
  /// How many of the line's moves are on the board.
  private(set) var ply: Int
  private(set) var fens: [String]
  private var moves: [LegalMove]
  /// The engine's best line from each position looked at; nil when there is none to play.
  private var bests: [String: EngineLine?] = [:]
  /// How deep the engine looked from each position.
  private var depths: [String: Int] = [:]

  init(game: [String]) {
    let walked = walkSan(game)
    self.game = Array(game.prefix(walked.moves.count))
    line = self.game
    ply = self.game.count
    fens = walked.fens
    moves = walked.moves
  }

  var fen: String { fens[ply] }
  /// On the game's own last position.
  var atEnd: Bool { ply == game.count && Array(line.prefix(ply)) == game }
  /// The move that led here.
  var last: LegalMove? { ply > 0 ? moves[ply - 1] : nil }
  /// The top move here, once the engine has said; nil while it thinks or with none.
  var top: LegalMove? { best?.pv.first.flatMap { applyUci(fen, $0) } }
  /// The engine's best line here, once it has said.
  var best: EngineLine? { bests[fen].flatMap { $0 } }
  /// How deep the engine looked here; 0 before it has.
  var depth: Int { depths[fen] ?? 0 }

  /// The move a step would make: forward plays the next one in the line, or the top move past its end;
  /// back takes the last one back.
  func stepMove(_ dir: Int) -> LegalMove? {
    if dir < 0 { return last }
    return ply < line.count ? moves[ply] : top
  }

  func canStep(_ dir: Int) -> Bool { stepMove(dir) != nil }

  func step(_ dir: Int) {
    guard let move = stepMove(dir) else { return }
    if dir < 0 {
      ply -= 1
    } else {
      if ply == line.count { extend(move) }
      ply += 1
    }
  }

  /// A move played on the board: it replaces whatever came after it.
  func play(_ move: LegalMove) {
    line = Array(line.prefix(ply))
    fens = Array(fens.prefix(ply + 1))
    moves = Array(moves.prefix(ply))
    extend(move)
    ply += 1
  }

  /// Asks the engine for the top move here, once per position.
  func findTop() async {
    let fen = self.fen
    guard bests[fen] == nil else { return }
    if legalMoves(fen).isEmpty {
      bests[fen] = .some(nil)
      return
    }
    let snap = await HintEngine.shared.analyse(fen, EngineLimits(depth: 14, movetime: 400, multiPv: 1))
    guard !Task.isCancelled else { return }
    bests[fen] = .some(snap.lines.first)
    depths[fen] = snap.depth
  }

  private func extend(_ move: LegalMove) {
    line.append(move.san)
    moves.append(move)
    fens.append(move.after)
  }
}
