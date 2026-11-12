import ChessCore
import Foundation
import Model

/// How a sitting begins, as `useRoundIntro` has it: "Growth" and the opening
/// full screen, then the way in played out on a locked board. A Home
/// recommendation skips both.
extension GrowthModel {
  /// How long the announcement holds, unless tapped away: `ANNOUNCE_MS`.
  public static let announceMs = Int(RunModel.announceMs * 1000)
  /// The beat between replayed moves: `REPLAY_MS`.
  public static let replayMs = 400

  public func planIntro() {
    let catalogue = tree
    let id = deepestNodeWithin(catalogue, launch.opening, run.path).id
    introOpening = id
    introName = catalogue.root.id == id ? launch.row.name : nil
    // A recommendation from Home goes straight to the board at its gap.
    if launch.gap != nil {
      introPath = []
      intro = .done
      settle()
      return
    }
    introPath = store.state.settings.autoplay ? Array(run.path.prefix(startLength)) : []
    intro = .announce
    let key = run.fen
    let clock = services.clock
    services.spawn { [weak self] in
      await clock.sleep(Double(Self.announceMs) / 1000)
      if self?.intro == .announce, self?.run.fen == key { self?.toBoard() }
    }
  }

  /// The intro's position while it runs, in place of the run's.
  public var introFen: String? {
    held ? walkSan(introPath).fens[min(introPly, introPath.count)] : nil
  }

  public var introLastMove: (from: String, to: String)? {
    lastMoveOf(Array(introPath.prefix(introPly)))
  }

  /// What the announcement says under "Growth".
  public var introTrail: [String] {
    if let introName { return [introName] }
    return store.catalog.map { selectionTrail(tree, $0, introOpening) } ?? []
  }

  /// Tap the announcement away.
  public func toBoard() {
    guard intro == .announce else { return }
    if introPath.isEmpty {
      intro = .done
      settle()
    } else {
      intro = .replay
      replayStep()
    }
  }

  public func skipIntro() {
    guard intro == .replay else { return }
    introPly = introPath.count
    intro = .done
    settle()
  }

  private func replayStep() {
    let clock = services.clock
    services.spawn { [weak self] in
      await clock.sleep(Double(Self.replayMs) / 1000)
      guard let self, self.intro == .replay else { return }
      if self.introPly < self.introPath.count {
        self.introPly += 1
        self.replayStep()
      } else {
        self.intro = .done
        self.settle()
      }
    }
  }
}
