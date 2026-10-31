import ChessCore
import Foundation
import Model

/// Debug builds play a sitting's answers for screenshots: `DRILL_PLAY=r,w`
/// (right, wrong, `c` Continue), then `DRILL_SHOW=line|moves|why`.
#if DEBUG
  private let debugEnv = ProcessInfo.processInfo.environment

  private func wrongMove(_ fen: String, _ right: [String]) -> LegalMove? {
    legalMoves(fen).first { !right.contains($0.san) && $0.piece == .p }
  }

  extension DrillSessionModel {
    func debugPlay() {
      guard let script = debugEnv["DRILL_PLAY"] else { return }
      Task { @MainActor in
        while held { try? await Task.sleep(for: .milliseconds(200)) }
        for step in script.split(separator: ",") {
          try? await Task.sleep(for: .milliseconds(1500))
          guard let item else { return }
          switch step {
          case "r": if let move = expectedMove { play(move) }
          case "w": if let move = wrongMove(item.fen, item.expected.map(\.san)) { play(move) }
          case "c": continueAfterMiss()
          default: break
          }
        }
        try? await Task.sleep(for: .milliseconds(1200))
        switch debugEnv["DRILL_SHOW"] {
        case "line": revealLine = true
        case "moves": showMoves = true
        case "why": why = true
        case "explore": explore = true
        default: break
        }
      }
    }
  }

  extension LineDrillModel {
    func debugPlay() {
      guard let script = debugEnv["DRILL_PLAY"] else { return }
      Task { @MainActor in
        while held { try? await Task.sleep(for: .milliseconds(200)) }
        for step in script.split(separator: ",") {
          try? await Task.sleep(for: .milliseconds(1200))
          while !(lines.phase == .play && mine) && lines.phase != .wrong && lines.phase != .done {
            try? await Task.sleep(for: .milliseconds(200))
          }
          switch step {
          case "r": if let move = expectedMove { play(move) }
          case "w": if let move = wrongMove(fen, expected.map { [$0] } ?? []) { play(move) }
          case "c": carryOnAfterMiss()
          case "n": nextLine()
          default: break
          }
        }
        try? await Task.sleep(for: .milliseconds(1200))
        if debugEnv["DRILL_SHOW"] == "why" { why = true }
      }
    }
  }
#endif
