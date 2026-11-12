import ChessCore
import Engine
import Game
import Model
import Observation

/// An engine line with its moves as SAN, as the screen shows it.
struct SanLine: Identifiable {
  var line: EngineLine
  var sans: [String]
  var id: Int { line.multipv }
}

/// Analysis's engine: `useEngine` with depth 16 and three lines, each finished
/// depth shown as it lands. A new position waits a moment, so scrubbing does
/// not thrash it.
@MainActor @Observable
final class AnalysisEngine {
  private(set) var snapshot: EngineSnapshot?
  /// Nil until the first search has started: "Starting…".
  private(set) var started = false
  private let engine: ChessEngine
  private var generation = 0

  init(engine: ChessEngine = HintEngine.shared) {
    self.engine = engine
  }

  /// The lines of the last snapshot, PVs as SAN from the position they were searched in.
  var sanLines: [SanLine] {
    guard let snapshot else { return [] }
    return snapshot.lines.map { line in
      var at = snapshot.fen
      var sans: [String] = []
      for uci in line.pv.prefix(24) {
        guard let move = applyUci(at, uci) else { break }
        sans.append(move.san)
        at = move.after
      }
      return SanLine(line: line, sans: sans)
    }
  }

  /// Search `fen` until done or cancelled; call from a `.task(id:)`.
  func run(_ fen: String?) async {
    // Depths the last search already sent on their way are dropped from here.
    generation += 1
    let gen = generation
    guard let fen else {
      snapshot = nil
      return
    }
    try? await Task.sleep(for: .milliseconds(220))
    if Task.isCancelled { return }
    started = true
    let final = await engine.analyse(fen, EngineLimits(depth: 16, multiPv: 3)) { [weak self] snap in
      Task { @MainActor in self?.take(snap, gen) }
      return Task.isCancelled
    }
    if !Task.isCancelled { take(final, gen) }
  }

  /// A depth from a search already replaced is dropped.
  private func take(_ snap: EngineSnapshot, _ gen: Int) {
    if gen == generation { snapshot = snap }
  }
}
