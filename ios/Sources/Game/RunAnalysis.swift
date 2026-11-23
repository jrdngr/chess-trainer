import ChessCore
import Engine
import Model
import Observation

/// A finished run, analysed on its own board: the game's moves to step back and forth
/// through, moves played on the board to try others, and the engine's eval and top move from each position.
/// Stepping forward goes through the game's moves while there are any, then plays the engine's top move.
/// A move played on the board starts your own line; stepping back over that move drops it and the game
/// comes back. A run that ended on a blunder has the engine's line that punished it, which Show plays out
/// from the blunder, a move at a time.
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
  /// Where your own line starts: the ply of the first move you played on the board, nil while on the game.
  public private(set) var branch: Int?
  /// The line as it was before your own line started, to come back to when you step back over it.
  private var base: (line: [String], moves: [LegalMove], fens: [String]) = ([], [], [])
  /// Show is playing the punishing line out; a step or a move of your own stops it.
  public private(set) var showing = false
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
  /// How many of the line's first moves are the game's own; the rest are engine moves.
  public var gameMoves: Int { min(branch ?? game.count, game.count) }
  /// On engine moves: past the game's end, or on your own line.
  public var onEngine: Bool { ply > gameMoves }
  /// On the game's own last position.
  public var atEnd: Bool { ply == game.count && Array(line.prefix(ply)) == game }
  /// On the game's end or the punishing line played from it, so the way the game ended still stands.
  public var onPunishment: Bool {
    let full = game + punish
    return ply >= game.count && ply <= full.count && Array(line.prefix(ply)) == Array(full.prefix(ply))
  }

  /// Show has nothing left to play from here: the board is on the punishing line's last move, so Show offers a replay.
  public var atPunishmentEnd: Bool { !punish.isEmpty && !showing && onPunishment && punishNext == nil }

  /// The punishing line's next move, while the board is on that line and it has more.
  public var punishNext: LegalMove? {
    guard onPunishment, ply < game.count + punish.count else { return nil }
    return applySan(fen, punish[ply - game.count])
  }

  /// One more move of the punishing line, when there is one.
  public func playPunish() {
    guard let move = punishNext else { return }
    if ply < line.count && moves[ply].san == move.san { ply += 1 } else { extendHere(move) }
  }

  /// Show: back to the blunder, with the game as played, and the punishing line plays from there.
  public func show() {
    guard !punish.isEmpty else { return }
    dropBranch()
    ply = game.count
    showing = true
  }

  /// While Show plays: the line's next move. Show stops once the line has none left.
  public func showNext() {
    guard showing else { return }
    playPunish()
    if punishNext == nil { showing = false }
  }

  /// The move that led here.
  public var last: LegalMove? { ply > 0 ? moves[ply - 1] : nil }
  /// The top move here, once the engine has said; nil while it thinks or with none.
  public var top: LegalMove? { best?.pv.first.flatMap { applyUci(fen, $0) } }
  /// The engine's best line here, once it has said.
  public var best: EngineLine? { bests[fen].flatMap { $0 } }
  /// How deep the engine looked here; 0 before it has.
  public var depth: Int { depths[fen] ?? 0 }

  /// The move a step would make: forward plays the line's next move (the game's, while there is one),
  /// else the top move shown; back takes the last one back.
  public func stepMove(_ dir: Int) -> LegalMove? {
    if dir < 0 { return last }
    return ply < line.count ? moves[ply] : top
  }

  public func canStep(_ dir: Int) -> Bool { stepMove(dir) != nil }

  public func step(_ dir: Int) {
    guard let move = stepMove(dir) else { return }
    showing = false
    if dir < 0 {
      ply -= 1
      if let branch, ply <= branch { dropBranch() }
    } else if ply < line.count {
      ply += 1
    } else {
      extend(move)
      ply += 1
    }
  }

  /// Straight to the line's `target`th move, kept within the line. Before your own line started, it is dropped.
  public func seek(_ target: Int) {
    showing = false
    ply = min(max(0, target), line.count)
    if let branch, ply <= branch { dropBranch() }
  }

  /// A move played on the board: the line's own next move is a step forward; any other starts your own line here,
  /// or carries it on, in place of whatever came after.
  public func play(_ move: LegalMove) {
    showing = false
    if ply < line.count && moves[ply].san == move.san {
      ply += 1
      return
    }
    if branch == nil {
      base = (line, moves, fens)
      branch = ply
    }
    extendHere(move)
  }

  /// Your own line goes, and the line it started from comes back.
  private func dropBranch() {
    guard branch != nil else { return }
    (line, moves, fens) = base
    base = ([], [], [])
    branch = nil
  }

  /// `move` played here, in place of whatever came after.
  private func extendHere(_ move: LegalMove) {
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
    // The engine is shared with the lenses: an answer cut short comes back empty, so ask again rather than keep it.
    for _ in 0..<3 {
      let snap = await engine.analyse(fen, EngineLimits(depth: 14, movetime: 400, multiPv: 1))
      guard !Task.isCancelled else { return }
      if let line = snap.lines.first, !line.pv.isEmpty {
        bests[fen] = .some(line)
        depths[fen] = snap.depth
        return
      }
    }
  }

  private func extend(_ move: LegalMove) {
    line.append(move.san)
    moves.append(move)
    fens.append(move.after)
  }
}
