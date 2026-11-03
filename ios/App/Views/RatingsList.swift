import Model
import SwiftUI

/// What a round did to your ratings, one line per opening it is handed.
/// Nothing at all when the round moved none of them.
struct RatingsList: View {
  struct Item {
    var id: String
    var ext: Bool
    var name: String
    var delta: Double
    var after: Double
  }

  var items: [Item]

  var body: some View {
    if !items.isEmpty {
      VStack(spacing: 0) {
        ForEach(Array(items.enumerated()), id: \.offset) { i, item in
          if i > 0 { Rectangle().fill(.white.opacity(0.07)).frame(height: 1) }
          row(item)
        }
      }
      .background(RoundedRectangle(cornerRadius: 18).fill(Theme.surface))
      .clipShape(RoundedRectangle(cornerRadius: 18))
    }
  }

  private func row(_ item: Item) -> some View {
    let rank = rankOf(item.after)
    let delta = Int(JSRound(item.delta))
    return HStack(spacing: 12) {
      Circle().fill(Color(hexString: (rank.held ?? UNRATED).color)).frame(width: 10, height: 10)
      VStack(alignment: .leading, spacing: 2) {
        Text(item.name).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.text).lineLimit(1)
        HStack(spacing: 6) {
          if item.ext {
            Text("Extensions").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.ext)
              .padding(.horizontal, 6).overlay(Capsule().strokeBorder(Theme.accent, lineWidth: 1.5))
          }
          Text(rank.heldLabel).font(.system(size: 12.5)).foregroundStyle(Theme.text3)
        }
        .lineLimit(1)
      }
      Spacer(minLength: 0)
      Text(delta >= 0 ? "+\(delta)" : "\(delta)").font(.system(size: 14).monospacedDigit())
        .foregroundStyle(item.delta < 0 ? Theme.bad : Theme.good)
      Text("\(Int(JSRound(item.after)))").font(.system(size: 14).monospacedDigit()).foregroundStyle(Theme.text3)
    }
    .padding(.horizontal, 16).padding(.vertical, 10).frame(minHeight: 54)
  }
}

/// A two-sided control.
struct SegmentedControl<Value: Hashable>: View {
  @Binding var value: Value
  var options: [(value: Value, label: String)]

  var body: some View {
    HStack(spacing: 2) {
      ForEach(options, id: \.value) { option in
        let active = option.value == value
        Button { value = option.value } label: {
          Text(option.label).font(.system(size: 13.5, weight: .semibold))
            .foregroundStyle(active ? Theme.text : Theme.text2)
            .lineLimit(1).minimumScaleFactor(0.8).padding(.horizontal, 6)
            .frame(maxWidth: .infinity, minHeight: 36)
            .background(RoundedRectangle(cornerRadius: 9).fill(active ? Theme.surface3 : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
      }
    }
    .padding(3)
    .background(RoundedRectangle(cornerRadius: 12).fill(Theme.surface))
    .animation(.easeOut(duration: 0.15), value: value)
  }
}
