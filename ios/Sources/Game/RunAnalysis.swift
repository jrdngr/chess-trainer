import ChessCore
import Engine
import Model
import Observation

/// A finished run, analysed on its own board: the game's moves to step back and forth
/// through, moves played on the board to try others, and the engine's eval and top move from each position.
/// Stepping forward always plays the top move shown, in the game or past its end; where the line
/// went another way, the rest of it gives way. A run that ended on a blunder has the engine's line that
/// punished it, which plays out past the game's end on its own.
@MainActor @Observable
public final class RunAnalysis {
  /// The game as played, its last move the one that ended it.
  public let game: [String]
  /// The engine's moves that punished the blunder the game ended on, as SAN; empty for any other ending.
  public let punish: [String]
  /// The line being looked at: the game, or another tried from a position in it.
  public private(set) var line: [String]
  /// How many of the line's moves are on the board.
  public private(set) var ply: Int
  public private(set) var fens: [String]
  private var moves: [LegalMove]
  /// The engine's best line from each position looked at; nil when there is none to play.
  private var bests: [String: EngineLine?] = [:]
  /// How deep the engine looked from each position.
  private var depths: [String: Int] = [:]

  private let engine: ChessEngine

  /// `punish` is the line after the game's last move, as UCI.
  public init(game: [String], punish: [String] = [], engine: ChessEngine) {
    self.engine = engine
    let walked = walkSan(game)
    self.game = Array(game.prefix(walked.moves.count))
    var at = walked.fens.last ?? START_FEN
    var sans: [String] = []
    if walked.moves.count == game.count {
      for uci in punish {
        guard let move = applyUci(at, uci) else { break }
        sans.append(move.san)
        at = move.after
      }
    }
    self.punish = sans
    line = self.game
    ply = self.game.count
    fens = walked.fens
    moves = walked.moves
  }

  public var fen: String { fens[ply] }
  /// On the game's own last position.
  public var atEnd: Bool { ply == game.count && Array(line.prefix(ply)) == game }
  /// On the game's end or the punishing line played from it, so the way the game ended still stands.
  public var onPunishment: Bool {
    let full = game + punish
    return ply >= game.count && ply <= full.count && Array(line.prefix(ply)) == Array(full.prefix(ply))
  }

  /// The punishing line's next move, while the board is on that line and it has more.
  public var punishNext: LegalMove? {
    guard onPunishment, ply < game.count + punish.count else { return nil }
    return applySan(fen, punish[ply - game.count])
  }

  /// One more move of the punishing line, when there is one.
  public func playPunish() {
    guard let move = punishNext else { return }
    if ply < line.count && moves[ply].san == move.san { ply += 1 } else { play(move) }
  }

  /// The move that led here.
  public var last: LegalMove? { ply > 0 ? moves[ply - 1] : nil }
  /// The top move here, once the engine has said; nil while it thinks or with none.
  public var top: LegalMove? { best?.pv.first.flatMap { applyUci(fen, $0) } }
  /// The engine's best line here, once it has said.
  public var best: EngineLine? { bests[fen].flatMap { $0 } }
  /// How deep the engine looked here; 0 before it has.
  public var depth: Int { depths[fen] ?? 0 }

  /// The move a step would make: forward plays the top move shown; back takes the last one back.
  public func stepMove(_ dir: Int) -> LegalMove? {
    dir < 0 ? last : top
  }

  public func canStep(_ dir: Int) -> Bool { stepMove(dir) != nil }

  public func step(_ dir: Int) {
    guard let move = stepMove(dir) else { return }
    if dir < 0 {
      ply -= 1
    } else if ply < line.count && moves[ply].san == move.san {
      ply += 1
    } else {
      play(move)
    }
  }

  /// Straight to the line's `target`th move, kept within the line.
  public func seek(_ target: Int) {
    ply = min(max(0, target), line.count)
  }

  /// A move played on the board: it replaces whatever came after it.
  public func play(_ move: LegalMove) {
    line = Array(line.prefix(ply))
    fens = Array(fens.prefix(ply + 1))
    moves = Array(moves.prefix(ply))
    extend(move)
    ply += 1
  }

  /// Asks the engine for the top move here, once per position.
  public func findTop() async {
    let fen = self.fen
    guard bests[fen] == nil else { return }
    if legalMoves(fen).isEmpty {
      bests[fen] = .some(nil)
      return
    }
    let snap = await engine.analyse(fen, EngineLimits(depth: 14, movetime: 400, multiPv: 1))
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
