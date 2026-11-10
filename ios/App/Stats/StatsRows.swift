import Model
import SwiftUI

/// A row in a list that opens something: a dot, a name over a line of meta,
/// a value, a chevron.
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
