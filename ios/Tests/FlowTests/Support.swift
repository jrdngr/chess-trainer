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
