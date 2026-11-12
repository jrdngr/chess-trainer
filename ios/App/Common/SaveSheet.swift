import ChessCore
import Game
import Model
import Shared
import SwiftUI

/// Saving a line, the same sheet everywhere a line comes in by hand.
/// The Playbook holds only book moves: a line that leaves the book is saved
/// up to where it leaves, and the rest is shown as not saved.
struct SaveSheet: View {
  var sans: [String]
  /// The side it goes in for, when the caller knows; otherwise the sheet asks.
  var color: ChessCore.Color? = nil
  var preferColor: ChessCore.Color? = nil
  /// Let the line be cut short by tapping a move.
  var trim = false
  var title = "Save line"
  var source: MoveSource
  /// A note for the line's last move.
  var note: String? = nil
  var onSaved: ((String, Int, [String]) -> Void)? = nil
  /// Take the line instead of saving it.
  var onKeep: (([String], ChessCore.Color) -> Void)? = nil
  var onClose: () -> Void

  @Environment(AppStore.self) private var store
  @Environment(Toasts.self) private var toasts
  @State private var depth: Int?
  @State private var picked: ChessCore.Color?

  var body: some View {
    let slice = Array(sans.prefix(min(depth ?? sans.count, sans.count)))
    let legal = walkSan(slice).fens.count == slice.count + 1
    let side = color ?? picked ?? preferColor ?? (slice.count % 2 == 1 ? .w : .b)
    let book = store.index.map { bookLength($0, slice) } ?? slice.count
    let leaves = book < slice.count

    ScrollView {
      VStack(alignment: .leading, spacing: 0) {
        Text(title).font(.system(size: 22, weight: .heavy)).foregroundStyle(Theme.text).padding(.bottom, 14)
        if trim {
          sectionHead("Line", aside: "Tap a move to trim")
          FlowMoves(sans: sans, cut: slice.count) { depth = $0 + 1 }
            .padding(.horizontal, 12).padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 18).fill(Theme.surface))
        }
        if color == nil {
          sectionHead("Side")
          SegmentedControl(value: Binding(get: { side }, set: { picked = $0 }), options: [(.w, "As White"), (.b, "As Black")])
        }
        if !slice.isEmpty {
          VStack(spacing: 0) {
            if book > 0 {
              row(label: "Playbook", line: snippet(slice, 0, book), value: moveCount(book), warn: false)
            }
            if leaves {
              if book > 0 { Rectangle().fill(.white.opacity(0.07)).frame(height: 1) }
              row(label: "Not in the book", line: snippet(slice, book, slice.count), value: "Not saved", warn: true)
            }
          }
          .background(RoundedRectangle(cornerRadius: 14).fill(Theme.surface2)).clipShape(RoundedRectangle(cornerRadius: 14))
          .padding(.top, 14)
        }
        Spacer().frame(height: 24)
        SheetButton(leaves && book > 0 ? "Save \(moveCount(book))" : "Save", style: .accent) { save(slice, book, side) }
          .disabled(!legal || book == 0)
      }
      .padding(20)
    }
  }

  private func row(label: String, line: String, value: String, warn: Bool) -> some View {
    let ink: SwiftUI.Color = warn ? Theme.warn : Theme.text2
    return HStack(spacing: 12) {
      if warn { Icon(name: "warn", size: 18).foregroundStyle(Theme.warn) }
      Text(label).font(.system(size: 14, weight: warn ? .semibold : .regular)).foregroundStyle(ink)
        .frame(maxWidth: .infinity, alignment: .leading)
      Text(line).font(.system(size: 13, design: .monospaced)).foregroundStyle(warn ? ink : Theme.text).lineLimit(1)
      Text(value).font(.system(size: 13)).foregroundStyle(warn ? ink : Theme.text3)
    }
    .padding(.horizontal, 14).padding(.vertical, 13)
    .background(warn ? Theme.warn.opacity(0.1) : .clear)
  }

  private func sectionHead(_ title: String, aside: String? = nil) -> some View {
    HStack {
      Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.text2)
      Spacer()
      if let aside { Text(aside).font(.system(size: 12)).foregroundStyle(Theme.text3) }
    }
    .padding(.horizontal, 4).padding(.top, 8).padding(.bottom, 8)
  }

  private func save(_ slice: [String], _ upTo: Int, _ side: ChessCore.Color) {
    let line = Array(slice.prefix(upTo))
    guard !line.isEmpty else { return }
    if let onKeep {
      onKeep(line, side)
      toasts.show("Saved")
      onClose()
      return
    }
    var added = 0
    var repId = ""
    store.update { state in
      repId = state.ensurePlaybook(side)
      added = state.addLine(repId, line, .fixed(source))
      if let note, upTo == slice.count, let rep = state.playbooks[repId], let tip = nodeAtLine(rep, line) {
        state.annotate(repId, tip.id, note)
      }
    }
    onSaved?(repId, added, line)
    toasts.show(added > 0 ? "\(added) added" : "Already in your Playbook")
    onClose()
  }
}

/// A line's moves wrapped over rows, past the cut drawn faint: `.strip.wrapped`.
struct FlowMoves: View {
  var sans: [String]
  var cut: Int
  var onTap: (Int) -> Void

  var body: some View {
    WrapLayout(spacing: 4) {
      ForEach(Array(sans.enumerated()), id: \.offset) { i, san in
        Button { onTap(i) } label: {
          HStack(spacing: 2) {
            if i % 2 == 0 { Text("\(i / 2 + 1).").fontWeight(.medium).foregroundStyle(i == cut - 1 ? .black.opacity(0.45) : Theme.text3) }
            Text(san)
          }
          .font(.system(size: 13.5, weight: .semibold).monospacedDigit())
          .foregroundStyle(i == cut - 1 ? Theme.background : Theme.text2)
          .padding(.horizontal, 10).padding(.vertical, 6)
          .background(RoundedRectangle(cornerRadius: 9).fill(i == cut - 1 ? Theme.text : Theme.surface2))
          .opacity(i >= cut ? 0.45 : 1)
        }
        .buttonStyle(.plain)
      }
    }
  }
}

/// Children laid out left to right, wrapping onto new rows.
struct WrapLayout: Layout {
  var spacing: CGFloat = 4

  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
    let width = proposal.width ?? .infinity
    var x: CGFloat = 0, y: CGFloat = 0, row: CGFloat = 0, widest: CGFloat = 0
    for view in subviews {
      let size = view.sizeThatFits(.unspecified)
      if x > 0 && x + size.width > width {
        y += row + spacing
        x = 0
        row = 0
      }
      x += size.width + spacing
      row = max(row, size.height)
      widest = max(widest, x - spacing)
    }
    return CGSize(width: proposal.width ?? widest, height: y + row)
  }

  func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
    var x = bounds.minX, y = bounds.minY, row: CGFloat = 0
    for view in subviews {
      let size = view.sizeThatFits(.unspecified)
      if x > bounds.minX && x + size.width > bounds.maxX {
        y += row + spacing
        x = bounds.minX
        row = 0
      }
      view.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
      x += size.width + spacing
      row = max(row, size.height)
    }
  }
}

/// A sheet's full-width button: `.btn`, `.btn.accent`, `.btn.danger`, `.btn.primary`.
struct SheetButton: View {
  enum Style { case plain, accent, danger, primary, soft }
  var title: String
  var icon: String?
  var style: Style
  var action: () -> Void
  @Environment(\.isEnabled) private var enabled

  init(_ title: String, icon: String? = nil, style: Style, action: @escaping () -> Void) {
    self.title = title
    self.icon = icon
    self.style = style
    self.action = action
  }

  var body: some View {
    let (fg, bg): (SwiftUI.Color, SwiftUI.Color) = switch style {
    case .plain: (Theme.text, Theme.surface2)
    case .soft: (Theme.text, Theme.surface)
    case .accent: (Theme.accentInk, Theme.accent)
    case .danger: (Theme.bad, Theme.bad.opacity(0.14))
    case .primary: (Theme.background, SwiftUI.Color(hex: 0xf5f5f7))
    }
    Button(action: action) {
      HStack(spacing: 8) {
        if let icon { Icon(name: icon, size: 18) }
        Text(title).lineLimit(1)
      }
      .font(.system(size: 16, weight: .bold)).foregroundStyle(fg)
      .frame(maxWidth: .infinity, minHeight: 50).padding(.horizontal, 12)
      .background(RoundedRectangle(cornerRadius: 16).fill(bg))
      .opacity(enabled ? 1 : 0.45)
    }
    .buttonStyle(.plain)
  }
}

/// "5.Ng5" or "5...Nf6": one move with its number.
func plyLabel(_ sans: [String], _ ply: Int) -> String {
  let n = ply / 2 + 1
  return ply % 2 == 0 ? "\(n).\(sans[ply])" : "\(n)...\(sans[ply])"
}

/// Part of a line, short: "1.e4 … 4.d3 Nf6", in full when it is three moves or fewer.
func snippet(_ sans: [String], _ from: Int, _ to: Int) -> String {
  var parts: [String] = []
  for ply in from..<to {
    parts.append(ply % 2 == 0 ? "\(ply / 2 + 1).\(sans[ply])" : ply == from ? plyLabel(sans, ply) : sans[ply])
  }
  if parts.count <= 3 { return parts.joined(separator: " ") }
  let last = to - 1
  let tail = last % 2 == 1 && last - 1 > from ? "\(parts[parts.count - 2]) \(parts[parts.count - 1])" : plyLabel(sans, last)
  return "\(parts[0]) \u{2026} \(tail)"
}

private func moveCount(_ plies: Int) -> String {
  let n = (plies + 1) / 2
  return "\(n) move\(n == 1 ? "" : "s")"
}

/// An eval in pawns from one side: "+0.3", "−0.6".
func pawns(_ whiteCp: Double, _ side: ChessCore.Color) -> String {
  let cp = side == .w ? whiteCp : -whiteCp
  if abs(cp) >= 9000 { return cp > 0 ? "Mate" : "Mated" }
  let value = JS.toFixed(abs(cp) / 100, 1)
  return cp > 0 ? "+\(value)" : cp < 0 ? "\u{2212}\(value)" : "0.0"
}
