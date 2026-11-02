import Foundation
import Model
import Observation
import SwiftUI

/// A budget for one move: only your own thinking is charged, and running out
/// ends nothing.
@MainActor @Observable
final class MoveClock {
  /// Seconds per move, or nil with no clock.
  let budget: Double?
  private(set) var elapsed: Double = 0
  @ObservationIgnored private var spent: Double = 0
  @ObservationIgnored private var startedAt: Double?
  @ObservationIgnored private var turnKey = ""
  @ObservationIgnored private var ticker: Task<Void, Never>?

  init(seconds: Double?) { budget = seconds }

  var left: Double? { budget.map { max(0, $0 - elapsed) } }
  var expired: Bool { left.map { $0 <= 0 } ?? false }

  /// Seconds spent on this move so far.
  func elapsedNow() -> Double {
    startedAt.map { spent + (Env.now() - $0) / 1000 } ?? spent
  }

  /// A new `key` is a fresh budget; the clock runs while `active`.
  func sync(key: String, active: Bool) {
    if key != turnKey {
      pause()
      turnKey = key
      spent = 0
      elapsed = 0
    }
    if active && startedAt == nil {
      startedAt = Env.now()
      ticker = Task { [weak self] in
        while !Task.isCancelled {
          try? await Task.sleep(for: .milliseconds(100))
          guard let self else { return }
          self.elapsed = self.elapsedNow()
        }
      }
    } else if !active {
      pause()
    }
  }

  func stop() { pause() }

  private func pause() {
    ticker?.cancel()
    if startedAt != nil { spent = elapsedNow() }
    startedAt = nil
  }
}

/// The clock in the app bar: a ring that empties as the budget goes. `ClockHud`.
struct ClockHud: View {
  var clock: MoveClock

  var body: some View {
    if let left = clock.left, let budget = clock.budget {
      let share = left / budget
      let ink = clock.expired ? Theme.bad.opacity(0.14) : share < 0.5 ? Theme.warn : Theme.good
      HStack(spacing: 7) {
        ZStack {
          Circle().stroke(Theme.surface3, lineWidth: 4)
          Circle().trim(from: 0, to: share).stroke(ink, lineWidth: 4).rotationEffect(.degrees(-90))
        }
        .frame(width: 14, height: 14)
        Text("\(Int(left.rounded(.up)))").frame(minWidth: 16, alignment: .trailing)
      }
      .font(.system(size: 13, weight: .bold).monospacedDigit())
      .foregroundStyle(clock.expired ? Theme.text3 : Theme.text)
      .padding(.leading, 6).padding(.trailing, 10).padding(.vertical, 4)
      .background(Capsule().fill(Theme.surface2))
      .shake(on: clock.expired)
    }
  }
}
