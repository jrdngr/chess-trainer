import Game
import Model
import SwiftUI

/// The run's current mission under the board: the turns left, its name and what it asks for.
struct GoalCard: View {
  let mission: Mission
  static let height: CGFloat = 66

  var body: some View {
    let tint = Self.tint(mission.kind)
    let left = max(0, missionTurnsLeft(mission))
    HStack(spacing: 12) {
      VStack(spacing: 1) {
        Text("\(left)").font(.system(size: 19, weight: .heavy).monospacedDigit())
        Text(left == 1 ? "TURN" : "TURNS").font(.system(size: 8.5, weight: .bold)).tracking(0.4).opacity(0.85)
      }
      .foregroundStyle(tint)
      .frame(width: 46, height: 44)
      .background(RoundedRectangle(cornerRadius: 12).fill(tint.opacity(0.14)))
      VStack(alignment: .leading, spacing: 3) {
        Text(missionTitle(mission.kind).uppercased()).font(.system(size: 11, weight: .bold)).tracking(0.6).foregroundStyle(tint)
        Text(missionTarget(mission.kind)).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.text)
      }
      .lineLimit(1)
      Spacer(minLength: 0)
    }
    .padding(.horizontal, 11)
    .frame(height: Self.height)
    .background(RoundedRectangle(cornerRadius: 16).fill(Theme.surface))
    .accessibilityElement(children: .combine)
  }

  static func tint(_ kind: MissionKind) -> SwiftUI.Color {
    switch kind {
    case .edge, .convert: return Theme.good
    case .lead: return Theme.accent
    case .dig: return Theme.warn
    case .plan: return PlanColors.plan
    }
  }
}
