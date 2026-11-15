import SwiftUI

/// A section's title, and an aside on the right.
struct StatsSection: View {
  var title: String
  var aside: String?
  var first = false

  var body: some View {
    HStack {
      Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.text2)
      Spacer()
      if let aside { Text(aside).font(.system(size: 12)).foregroundStyle(Theme.text3) }
    }
    .padding(.horizontal, 4).padding(.top, first ? 8 : 24).padding(.bottom, 8)
  }
}

/// A plain surface: `.card`.
struct StatsCard<Content: View>: View {
  @ViewBuilder var content: Content

  var body: some View {
    VStack(alignment: .leading, spacing: 0) { content }
      .padding(16).frame(maxWidth: .infinity, alignment: .leading)
      .background(RoundedRectangle(cornerRadius: 16).fill(Theme.surface))
  }
}

/// Small print under a control: `.note`.
struct StatsNote: View {
  var text: Text
  var center = false

  var body: some View {
    text.font(.system(size: 12)).foregroundStyle(Theme.text3).lineSpacing(2.5)
      .multilineTextAlignment(center ? .center : .leading)
      .frame(maxWidth: .infinity, alignment: center ? .center : .leading)
      .padding(.horizontal, 4)
  }
}

/// A change as colored text: green when it is good news, red when not.
struct StatsBadge: View {
  var text: String
  var good: Bool

  var body: some View {
    let color = good ? Theme.good : Theme.bad
    Text(text).font(.system(size: 13, weight: .semibold).monospacedDigit()).foregroundStyle(color)
  }
}
