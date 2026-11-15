import SwiftUI

/// A two-sided control.
struct SegmentedControl<Value: Hashable>: View {
  @Binding var value: Value
  var options: [(value: Value, label: String)]
  /// The color behind the options.
  var track = Theme.surface

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
    .background(RoundedRectangle(cornerRadius: 12).fill(track))
    .animation(.easeOut(duration: 0.15), value: value)
  }
}
