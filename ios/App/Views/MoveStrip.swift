import SwiftUI

/// How a move reads in the strip.
enum MoveTone { case mine, theirs, ghost, bad, good }

struct StripItem {
  var san: String
  /// Move number shown before the move, e.g. "12.".
  var label: String?
  var tone: MoveTone?
  var current = false
  /// Cursor position this chip jumps to; nil makes it unclickable.
  var seek: Int?
}

/// A scrolling row of moves with a cursor and arrows: `Strip` in `ui.tsx`.
struct MoveStrip: View {
  var items: [StripItem]
  var cursor: Int
  var max: Int
  var onSeek: (Int) -> Void
  /// Shown when there are no moves yet.
  var hint: String? = nil

  var body: some View {
    HStack(spacing: 6) {
      arrow("backward.end", disabled: cursor == 0) { onSeek(0) }
      arrow("chevron.left", disabled: cursor == 0) { onSeek(cursor - 1) }
      ScrollViewReader { proxy in
        ScrollView(.horizontal, showsIndicators: false) {
          HStack(spacing: 4) {
            if items.isEmpty, let hint { Text(hint).font(.system(size: 13)).foregroundStyle(Theme.text3).padding(.leading, 4) }
            ForEach(Array(items.enumerated()), id: \.offset) { i, item in chip(item).id(i) }
          }
          .padding(.vertical, 2)
        }
        .onAppear { scroll(proxy, animated: false) }
        .onChange(of: cursor) { scroll(proxy, animated: true) }
      }
      .frame(minHeight: 38)
      arrow("chevron.right", disabled: cursor >= max) { onSeek(cursor + 1) }
    }
  }

  /// Keeps the current move in view.
  private func scroll(_ proxy: ScrollViewProxy, animated: Bool) {
    let index = items.firstIndex(where: \.current) ?? 0
    if animated { withAnimation { proxy.scrollTo(index, anchor: .center) } } else { proxy.scrollTo(index, anchor: .center) }
  }

  private func arrow(_ icon: String, disabled: Bool, _ action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Image(systemName: icon).font(.system(size: 16, weight: .semibold)).frame(width: 38, height: 38)
        .background(Circle().fill(Theme.surface))
    }
    .foregroundStyle(Theme.text).disabled(disabled).opacity(disabled ? 0.4 : 1)
  }

  private func chip(_ item: StripItem) -> some View {
    let (fg, bg) = colors(item)
    return Button { if let seek = item.seek { onSeek(seek) } } label: {
      HStack(spacing: 2) {
        if let label = item.label { Text(label).fontWeight(.medium).foregroundStyle(numberColor(item)) }
        Text(item.san)
      }
      .font(.system(size: 13.5, weight: .semibold).monospacedDigit())
      .foregroundStyle(fg)
      .padding(.horizontal, 10).padding(.vertical, 6)
      .background(RoundedRectangle(cornerRadius: 9).fill(bg))
      .overlay {
        if item.current && (item.tone == .bad || item.tone == .good) { RoundedRectangle(cornerRadius: 9).strokeBorder(fg, lineWidth: 2) }
      }
      .opacity(item.tone == .ghost ? 0.45 : 1)
    }
    .buttonStyle(.plain)
  }

  private func colors(_ item: StripItem) -> (SwiftUI.Color, SwiftUI.Color) {
    switch item.tone {
    case .bad: return (Theme.bad, Theme.bad.opacity(0.14))
    case .good: return (Theme.good, Theme.good.opacity(0.14))
    default:
      if item.current { return (Theme.background, Theme.text) }
      return item.tone == .mine ? (Theme.text, Theme.surface3) : (Theme.text2, Theme.surface)
    }
  }

  private func numberColor(_ item: StripItem) -> SwiftUI.Color {
    if item.tone == .bad || item.tone == .good || item.tone == .mine { return colors(item).0.opacity(0.5) }
    return item.current ? .black.opacity(0.45) : Theme.text3
  }
}
