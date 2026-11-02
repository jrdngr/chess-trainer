import Foundation
import Model
import SwiftUI

/// The schedule of the position cards in scope, under Drill's setup: what
/// comes due this week, and where each card stands.
struct DrillSchedule: View {
  let cards: [Card]
  /// Positions in scope, cards or not.
  let positions: Int

  private static let young = SwiftUI.Color(hex: 0x7dd3fc)

  var body: some View {
    let now = Env.now()
    let week = forecast(cards, 7, now)
    let maxWeek = max(1, week.max() ?? 0)
    let mastery = masteryBuckets(cards)
    let unseen = positions - cards.count + mastery.unseen
    let ret = retention(cards)
    VStack(alignment: .leading, spacing: 0) {
      PlaySection(title: "This week", aside: "\(week.reduce(0, +)) reviews")
      HStack(alignment: .bottom, spacing: 6) {
        ForEach(0..<7, id: \.self) { i in
          VStack(spacing: 6) {
            Spacer(minLength: 0)
            RoundedRectangle(cornerRadius: 4).fill(i == 0 ? Theme.accent : Theme.surface3)
              .frame(height: max(3, 40 * max(0.04, Double(week[i]) / Double(maxWeek))))
            Text(i == 0 ? "Now" : dayLabel(now + Double(i) * DAY)).font(.system(size: 10.5, weight: .semibold)).foregroundStyle(Theme.text3)
          }
          .frame(maxWidth: .infinity)
        }
      }
      .frame(height: 64).padding(16).background(card)
      PlaySection(title: "Mastery", aside: ret.map { "\(Int(($0 * 100).rounded()))% recall" } ?? "\(positions) positions")
      VStack(alignment: .leading, spacing: 12) {
        GeometryReader { geo in
          let parts = [(mastery.mature, Theme.good), (mastery.young, Self.young), (mastery.learning, Theme.warn), (unseen, Theme.surface3)]
          HStack(spacing: 2) {
            ForEach(Array(parts.enumerated()), id: \.offset) { _, part in
              if part.0 > 0 {
                RoundedRectangle(cornerRadius: 2).fill(part.1)
                  .frame(width: max(0, geo.size.width * Double(part.0) / Double(max(1, positions)) - 2))
              }
            }
            Spacer(minLength: 0)
          }
        }
        .frame(height: 8).background(Capsule().fill(Theme.surface2)).clipShape(Capsule())
        AnalysisFlowLayout(spacing: 8) {
          pill(mastery.mature, "mature", Theme.good)
          pill(mastery.young, "young", Self.young)
          pill(mastery.learning, "learning", Theme.warn)
          pill(unseen, "unseen", Theme.surface3)
        }
      }
      .padding(16).background(card)
    }
  }

  private var card: some View { RoundedRectangle(cornerRadius: 18).fill(Theme.surface) }

  private func pill(_ n: Int, _ label: String, _ dot: SwiftUI.Color) -> some View {
    HStack(spacing: 6) {
      Circle().fill(dot).frame(width: 7, height: 7)
      Text("\(n)").fontWeight(.bold).foregroundStyle(Theme.text)
      Text(label)
    }
    .font(.system(size: 13, weight: .semibold).monospacedDigit()).foregroundStyle(Theme.text2)
    .padding(.horizontal, 11).padding(.vertical, 6).background(Capsule().fill(Theme.surface2))
  }

  private func dayLabel(_ ms: Double) -> String {
    let f = DateFormatter()
    f.dateFormat = "EEEEE"
    return f.string(from: Date(timeIntervalSince1970: ms / 1000))
  }
}
