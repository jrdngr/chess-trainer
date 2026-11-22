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

/// After a blunder, nothing plays until Show: it plays the line that punished it past the game's end, a move a beat,
/// and stops at its end; the line can be stepped back through, and Show plays it again from the blunder, even after
/// another line was tried. While the board is on it the game's ending still stands; a step or a move of your own stops Show.
@MainActor @Test func showPlaysOutTheBlundersPunishment() async throws {
  let game = ["e4", "d5", "Qg4"]
  let analysis = RunAnalysis(game: game, punish: ["c8g4", "f1e2"], engine: FixedEngine(tops: [:]))
  #expect(analysis.punish == ["Bxg4", "Be2"])
  #expect(analysis.atEnd && analysis.onPunishment && !analysis.showing, "it waits for Show")
  analysis.showNext()
  #expect(analysis.atEnd, "no move before Show")
  analysis.show()
  analysis.showNext()
  #expect(analysis.showing && analysis.line == game + ["Bxg4"])
  analysis.showNext()
  #expect(analysis.line == game + ["Bxg4", "Be2"] && analysis.ply == 5)
  #expect(!analysis.showing && analysis.onPunishment && analysis.punishNext == nil, "it stops at the line's end")
  analysis.show()
  #expect(analysis.atEnd && analysis.showing, "Show again starts from the blunder")
  analysis.showNext()
  #expect(analysis.ply == 4 && analysis.line.count == 5, "back along the line, it plays its own moves again")
  analysis.step(-1)
  #expect(!analysis.showing, "a step stops it")
  analysis.seek(1)
  let other = try #require(applySan(analysis.fen, "c5"))
  analysis.play(other)
  #expect(!analysis.onPunishment && analysis.punishNext == nil)
  analysis.show()
  #expect(analysis.line == game && analysis.atEnd, "Show brings the game back after another line was tried")
  analysis.showNext()
  analysis.play(try #require(applySan(analysis.fen, "Nf3")))
  #expect(!analysis.showing, "a move of your own stops it")
}
