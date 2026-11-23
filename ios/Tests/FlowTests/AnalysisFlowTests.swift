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

/// After the game, a step forward goes through the game's own moves, even where the engine's top move differs,
/// and plays the engine's top move only past the game's end. Those engine moves stay in the line, so going back
/// into the game and forward again goes through the game, then the same engine moves.
@MainActor @Test func analysisStepsThroughTheGameThenTheEngine() async throws {
  let game = ["e4", "e5", "Nf3", "Nc6"]
  let afterE4E5 = try #require(walkSan(["e4", "e5"]).fens.last)
  let key = afterE4E5.split(separator: " ").prefix(2).joined(separator: " ")
  let analysis = RunAnalysis(game: game, engine: FixedEngine(tops: [key: "b1c3"]))
  #expect(analysis.atEnd && !analysis.onEngine)
  analysis.seek(2)
  await analysis.findTop()
  #expect(analysis.top?.san == "Nc3", "the arrow still shows the engine's top move")
  #expect(analysis.stepMove(1)?.san == "Nf3", "not the engine's Nc3")
  analysis.step(1)
  analysis.step(1)
  #expect(analysis.line == game && analysis.atEnd && !analysis.onEngine)

  await analysis.findTop()
  let top = try #require(analysis.top)
  analysis.step(1)
  #expect(analysis.line == game + [top.san] && analysis.ply == 5 && analysis.onEngine, "past the end, the engine's top move")
  #expect(analysis.gameMoves == 4)

  analysis.seek(1)
  #expect(analysis.line == game + [top.san], "going back keeps the engine's moves past the end")
  for _ in 0..<4 { analysis.step(1) }
  #expect(analysis.ply == 5 && analysis.line == game + [top.san])
}

/// A move played on the board starts your own line in place of the game's later moves; forward on it plays the
/// engine's top move. Stepping back over the move that started it drops it and the game comes back. The line's own
/// next move played on the board is only a step forward.
@MainActor @Test func analysisOwnLineGivesWayToTheGame() async throws {
  let game = ["e4", "e5", "Nf3", "Nc6"]
  let analysis = RunAnalysis(game: game, engine: FixedEngine(tops: [:]))
  analysis.seek(2)
  analysis.play(try #require(applySan(analysis.fen, "Nf3")))
  #expect(analysis.branch == nil && analysis.line == game && analysis.ply == 3, "the game's own move is a step")

  analysis.step(-1)
  analysis.play(try #require(applySan(analysis.fen, "Bc4")))
  #expect(analysis.line == ["e4", "e5", "Bc4"] && analysis.branch == 2 && analysis.gameMoves == 2 && analysis.onEngine)
  await analysis.findTop()
  let top = try #require(analysis.top)
  analysis.step(1)
  #expect(analysis.line == ["e4", "e5", "Bc4", top.san] && analysis.ply == 4, "forward on your line: the engine's top move")
  analysis.step(-1)
  analysis.step(1)
  #expect(analysis.line == ["e4", "e5", "Bc4", top.san] && analysis.ply == 4, "a step back within your line keeps it")

  analysis.step(-1)
  analysis.step(-1)
  #expect(analysis.branch == nil && analysis.line == game && analysis.ply == 2 && !analysis.onEngine, "back over your move: the game again")
  #expect(analysis.stepMove(1)?.san == "Nf3")

  analysis.seek(3)
  analysis.play(try #require(applySan(analysis.fen, "a6")))
  #expect(analysis.branch == 3)
  analysis.seek(1)
  #expect(analysis.branch == nil && analysis.line == game, "tapping a move before your line drops it")

  analysis.seek(4)
  analysis.play(try #require(applySan(analysis.fen, "Bb5")))
  analysis.step(-1)
  #expect(analysis.branch == nil && analysis.atEnd, "your line past the end goes too, back to the game's end")
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
  #expect(analysis.branch == nil && analysis.atEnd, "Show brings the game back after another line was tried")
  analysis.showNext()
  analysis.play(try #require(applySan(analysis.fen, "Nf3")))
  #expect(!analysis.showing, "a move of your own stops it")
}
