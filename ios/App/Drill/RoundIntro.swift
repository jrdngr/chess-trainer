import ChessCore
import Observation
import SwiftUI

/// How a Drill round begins: the mode and the opening announced full
/// screen, then the way to the first position played out on a locked board,
/// the opening on a pill over it.
@MainActor @Observable
final class RoundIntro {
  enum Stage { case announce, replay, done }
  let mode: String
  let trail: [String]
  /// The moves to the first position; empty for a round from move one.
  let path: [String]
  private(set) var stage = Stage.announce
  private(set) var ply = 0
  private(set) var pulse = false
  private let fens: [String]
  private var task: Task<Void, Never>?

  init(mode: String, trail: [String], path: [String], autoplay: Bool) {
    self.mode = mode
    self.trail = trail
    self.path = autoplay ? path : []
    fens = walkSan(autoplay ? path : []).fens
  }

  /// Announcing or replaying: the board is locked and the clock waits.
  var held: Bool { stage != .done }
  var replaying: Bool { stage == .replay }
  /// The replay's position while it runs.
  var fen: String? { held ? fens[min(ply, fens.count - 1)] : nil }
  var lastMove: (from: String, to: String)? { held ? lastMoveOf(Array(path.prefix(ply))) : nil }
  var name: String { trail.last ?? "" }
  /// The pill stays over a round from move one until the first move.
  func showsPill(moved: Bool) -> Bool { replaying || (stage == .done && path.isEmpty && !moved) }

  func begin() {
    guard task == nil else { return }
    task = Task { [weak self] in
      try? await Task.sleep(for: .milliseconds(2500))
      self?.toBoard()
    }
  }

  /// The announcement tapped away, or timed out.
  func toBoard() {
    guard stage == .announce else { return }
    task?.cancel()
    if path.isEmpty {
      stage = .done
      return
    }
    stage = .replay
    task = Task { [weak self] in
      while let self, self.stage == .replay {
        try? await Task.sleep(for: .milliseconds(400))
        if Task.isCancelled { return }
        if self.ply < self.path.count { self.ply += 1 } else { self.finish() }
      }
    }
  }

  /// The replay tapped through.
  func skip() {
    guard stage == .replay else { return }
    task?.cancel()
    ply = path.count
    finish()
  }

  func stop() { task?.cancel() }

  private func finish() {
    stage = .done
    pulse = true
    Task { [weak self] in
      try? await Task.sleep(for: .milliseconds(900))
      self?.pulse = false
    }
  }
}

/// Over the board while a round begins: the pill, tap-to-skip and the pulse.
struct IntroOverlay: View {
  var intro: RoundIntro
  var moved: Bool

  var body: some View {
    ZStack(alignment: .top) {
      if intro.replaying { Color.clear.contentShape(Rectangle()).onTapGesture { intro.skip() } }
      if intro.showsPill(moved: moved) {
        HStack(spacing: 8) {
          if intro.replaying {
            Text("Autoplay").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.background)
              .padding(.horizontal, 10).padding(.vertical, 4).background(Capsule().fill(Theme.accent))
          }
          Text(intro.name).font(.system(size: 15, weight: .bold)).foregroundStyle(Theme.text).lineLimit(1)
        }
        .padding(.leading, intro.replaying ? 8 : 16).padding(.trailing, 16).padding(.vertical, 8)
        .background(Capsule().fill(Theme.surface)).shadow(color: .black.opacity(0.5), radius: 15, y: 10)
        .allowsHitTesting(false)
        // Over the gap above the board, not on the back rank's pieces.
        .offset(y: -42)
        .introPillIn().id(intro.replaying)
      }
      if intro.pulse { IntroPulse() }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
  }
}
