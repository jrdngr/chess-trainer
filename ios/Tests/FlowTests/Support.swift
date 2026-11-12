import ChessCore
import Engine
import Foundation
import Game

/// The app's book, from the checkout.
let BOOK = URL(fileURLWithPath: #filePath)
  .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
  .appendingPathComponent("Resources/book.json")

/// A fresh install, played headless with the scripted engine.
@MainActor
func headless<T>(seed: UInt32 = 1, _ body: (HeadlessApp) async throws -> T) async throws -> T {
  try await HeadlessApp.run(book: BOOK, seed: seed, body)
}

/// The scripted engine's move here, as SAN.
func goodMove(_ fen: String) -> String? {
  ScriptedEngine().lines(fen, EngineLimits(multiPv: 1)).first?.pv.first.flatMap { applyUci(fen, $0)?.san }
}

/// A move that puts a piece where the opponent takes it for nothing.
func freeCapture(_ fen: String) -> String? {
  legalMoves(fen).first { move in
    move.piece != .k && move.piece != .p
      && legalMoves(move.after).contains { $0.to == move.to }
      && !legalMoves(move.after).contains { reply in reply.to == move.to && legalMoves(reply.after).contains { $0.to == move.to } }
  }?.san
}
