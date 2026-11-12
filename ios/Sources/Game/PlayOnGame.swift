import ChessCore
import Engine
import Model
import Observation

/// A game carried on from the end of a line, against the engine: your own
/// colour, a short fixed think, take-backs a pair at a time, and nothing recorded.
@MainActor @Observable
public final class PlayOnGame {
  public let from: String
  public let color: ChessCore.Color
  public private(set) var sans: [String] = []
  /// The engine's last word on the position, once it has said.
  public private(set) var best: EngineLine?
  @ObservationIgnored private let services: GameServices
  @ObservationIgnored private var thinking: Task<Void, Never>?

  public init(from: String, color: ChessCore.Color, services: GameServices) {
    self.from = from
    self.color = color
    self.services = services
    think()
  }

  public var fens: [String] { walkSan(sans, from).fens }
  public var fen: String { fens.last! }
  public var status: PositionStatus { positionStatus(fen) }
  /// The engine is to move.
  public var engineTurn: Bool { fenTurn(fen) != color }
  public var won: Bool { status.checkmate && fenTurn(fen) != color }
  /// Your moves on the board, for Take back.
  public var yourMoves: Int {
    let fens = self.fens
    return sans.indices.filter { fenTurn(fens[$0]) == color }.count
  }

  /// How it ended, once it has.
  public var result: String? {
    let status = self.status
    guard status.gameOver else { return nil }
    if status.checkmate { return won ? "Checkmate \u{2014} you won" : "Checkmate \u{2014} you lost" }
    return status.stalemate ? "Stalemate" : "Drawn"
  }

  /// Your move on the board.
  public func play(_ move: LegalMove) {
    guard !engineTurn, !status.gameOver, applySan(fen, move.san) != nil else { return }
    services.emit(.buzz(10))
    sans.append(move.san)
    think()
  }

  /// Take back your last move and the reply to it.
  public func takeBack() {
    guard yourMoves > 0, !engineTurn else { return }
    sans.removeLast(min(2, sans.count))
    think()
  }

  public func stop() { thinking?.cancel() }

  /// The engine's eval, and its move when it is to play.
  private func think() {
    thinking?.cancel()
    let fen = self.fen
    let moving = engineTurn && !status.gameOver
    let engine = services.engine("play-on")
    let clock = services.clock
    best = nil
    thinking = services.spawn { [weak self] in
      if moving { await clock.sleep(0.12) }
      guard !Task.isCancelled else { return }
      let snap = await engine.analyse(fen, EngineLimits(movetime: 700, multiPv: 1))
      guard let self, !Task.isCancelled, self.fen == fen else { return }
      self.best = snap.lines.first
      if moving, let uci = self.best?.pv.first, let move = applyUci(fen, uci) {
        self.sans.append(move.san)
        self.think()
      }
    }
  }
}
