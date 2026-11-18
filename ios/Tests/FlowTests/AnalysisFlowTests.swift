import ChessCore
import Engine
import Game
import Model
import Testing

/// An engine whose top move is fixed per position (by FEN's board and side), else the first legal move.
private struct FixedEngine: ChessEngine {
  let tops: [String: String]
  func analyse(_ fen: String, _ limits: EngineLimits, onUpdate: @escaping @Sendable (EngineSnapshot) -> Bool) async -> EngineSnapshot {
    let key = fen.split(separator: " ").prefix(2).joined(separator: " ")
    let uci = tops[key] ?? legalMoves(fen).first?.uci ?? ""
    return EngineSnapshot(lines: [EngineLine(multipv: 1, depth: 14, cp: 0, mate: nil, pv: [uci])], depth: 14, nodes: 1, thinking: false, fen: fen)
  }
}

/// After the game, the analysis board's step forward always plays the top move it shows,
/// even where the game went another way.
@MainActor @Test func analysisStepsPlayTheTopMoveShown() async throws {
  let game = ["e4", "e5", "Nf3", "Nc6"]
  let afterE4E5 = try #require(walkSan(["e4", "e5"]).fens.last)
  let key = afterE4E5.split(separator: " ").prefix(2).joined(separator: " ")
  let analysis = RunAnalysis(game: game, engine: FixedEngine(tops: [key: "b1c3"]))
  analysis.seek(2)
  await analysis.findTop()
  #expect(analysis.top?.san == "Nc3")
  #expect(analysis.stepMove(1)?.san == "Nc3", "not the game's Nf3")
  analysis.step(1)
  #expect(analysis.line == ["e4", "e5", "Nc3"], "the game's moves after it give way")
  #expect(analysis.ply == 3)

  analysis.step(-1)
  await analysis.findTop()
  analysis.step(1)
  #expect(analysis.line == ["e4", "e5", "Nc3"] && analysis.ply == 3, "the same top move steps along the line")

  analysis.step(1)
  #expect(analysis.line.count == 3, "no step before the engine has a top move")
  await analysis.findTop()
  let top = try #require(analysis.top)
  analysis.step(1)
  #expect(analysis.line.last == top.san && analysis.ply == 4)
}
