import Model
import SwiftUI

/// A row in a list that opens something: a dot, a name over a line of meta,
/// a value, a chevron. `.list-row` as `StatsScreen.tsx` uses it.
struct StatsRow: View {
  var dot: Color?
  var title: String
  var meta: String
  var value: String
  /// The dot after the name rather than before it, as a variation's tier.
  var dotTrailing = false
  var onTap: () -> Void

  var body: some View {
    Button(action: onTap) {
      HStack(spacing: 12) {
        if !dotTrailing, let dot { Circle().fill(dot).frame(width: 10, height: 10) }
        VStack(alignment: .leading, spacing: 2) {
          Text(title).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.text).lineLimit(1)
          Text(meta).font(.system(size: 12.5)).foregroundStyle(Theme.text3).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        if dotTrailing, let dot { Circle().fill(dot).frame(width: 10, height: 10) }
        Text(value).font(.system(size: 14).monospacedDigit()).foregroundStyle(Theme.text2)
        Icon(name: "chevron", size: 18).foregroundStyle(Theme.text)
      }
      .padding(.horizontal, 16).padding(.vertical, 10).frame(minHeight: 54).contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }
}

/// One opening in a ratings list: its tier, where it sits, and its rating. `RatedRow`.
struct RatedRow: View {
  var entry: Ranked
  var onOpen: (String) -> Void

  var body: some View {
    let own = entry.stats
    let rank = rankOf(own.rating, own.rated)
    StatsRow(
      dot: Color(hexString: (rank.held ?? UNRATED).color), title: entry.node.name,
      meta: rank.heldLabel + (entry.trail.isEmpty ? "" : " \u{00b7} \(entry.trail)"),
      value: own.rated == 0 ? "\u{2014}" : ratingText(own.rating)
    ) { onOpen(entry.node.id) }
  }
}

/// Where a rating stands on its ladder, and the rungs already held. `Ladder`.
struct StatsLadder: View {
  var rating: Double
  var rated: Int

  var body: some View {
    let rank = rankOf(rating, rated)
    VStack(spacing: 6) {
      RankBar(rank: rank) {
        Text(rated == 0 ? NEW_LABEL : "\(ratingText(rating))/\(ratingText(rank.ceiling))")
          .font(.system(size: 12.5, weight: .semibold).monospacedDigit()).foregroundStyle(Theme.text2)
      }
      HStack(spacing: 3) {
        ForEach(Array(TIERS.enumerated()), id: \.offset) { i, tier in
          RoundedRectangle(cornerRadius: 3).fill(Color(hexString: tier.color)).frame(height: 6)
            .opacity(i < rank.reached ? 1 : 0.25)
        }
      }
      .padding(.top, 8)
      .accessibilityHidden(true)
    }
  }
}
