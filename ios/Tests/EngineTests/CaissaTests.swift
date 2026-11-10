import ChessCore
import Model
import Testing

@testable import Engine

/// Caissa runs only with its network (`scripts/fetch-caissa-net.sh`).
@Suite(.enabled(if: EngineKind.caissa.available))
struct CaissaTests {
  @Test func findsMateInOneFromWhitesSide() async throws {
    let engine = try #require(CaissaEngine())
    // Black to move mates with Qh4# (fool's mate); White's frame makes it negative.
    let fen = "rnbqkbnr/pppp1ppp/8/4p3/6P1/5P2/PPPPP2P/RNBQKBNR b KQkq - 0 2"
    let snap = await engine.analyse(fen, EngineLimits(depth: 6, multiPv: 1))
    #expect(snap.lines.first?.pv.first == "d8h4")
    #expect(snap.lines.first?.mate == -1)
  }

  @Test func searchmovesAndMultiPvKeepToTheMovesAsked() async throws {
    let engine = try #require(CaissaEngine())
    let fen = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"
    let snap = await engine.analyse(fen, EngineLimits(depth: 8, multiPv: 5, searchmoves: ["e2e4", "a2a4"]))
    #expect(Set(snap.lines.compactMap(\.pv.first)) == ["e2e4", "a2a4"])
    // 1.e4 scores well above 1.a4, both in White's frame.
    let e4 = try #require(snap.lines.first { $0.pv.first == "e2e4" }?.cp)
    let a4 = try #require(snap.lines.first { $0.pv.first == "a2a4" }?.cp)
    #expect(e4 > a4)
    #expect(snap.depth == 8)
  }

  @Test func onUpdateCanStopTheSearch() async throws {
    let engine = try #require(CaissaEngine())
    let fen = "r1bqkbnr/pppp1ppp/2n5/4p3/4P3/5N2/PPPP1PPP/RNBQKB1R w KQkq - 2 3"
    let snap = await engine.analyse(fen, EngineLimits(depth: 30, movetime: 4000, multiPv: 1)) { $0.depth >= 5 }
    #expect(snap.depth == 5)
    #expect(snap.lines.first?.pv.isEmpty == false)
  }

  @Test func castlingComesOutAsUci() async throws {
    let engine = try #require(CaissaEngine())
    let fen = "r1bqk2r/pppp1ppp/2n2n2/2b1p3/2B1P3/5N2/PPPP1PPP/RNBQK2R w KQkq - 4 4"
    let snap = await engine.analyse(fen, EngineLimits(depth: 4, multiPv: 1, searchmoves: ["e1g1"]))
    #expect(snap.lines.first?.pv.first == "e1g1")
  }
}
