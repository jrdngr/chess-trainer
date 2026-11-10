import ChessCore
import Model
import SwiftUI

/* The opening browser's lists, shared by the browser and onboarding's Pick
 * openings. */

/// A suggestion's reason, in its own color: `WHY_COLOR`.
let WHY_COLOR: [ReasonKind: UInt32] = [.hole: 0xf97316, .like: 0x2dd4bf, .style: 0xa855f7]

/// Which side's rows a list shows.
enum SideFilter: Hashable { case both, w, b }

/// One level opened below a list, with its rows.
struct BrowseLevel {
  var label: String
  var items: [BrowseItem]
}

/// A heading and the rows under it.
struct BrowseBlock {
  var head: String?
  var rows: [BrowseRow]
}

/// A heading left with nothing under it, once the side filter has had its say. `dropEmptyHeads`.
func dropEmptyHeads(_ items: [BrowseItem]) -> [BrowseItem] {
  items.enumerated().filter { i, item in
    guard case .head = item else { return true }
    guard i + 1 < items.count, case .row = items[i + 1] else { return false }
    return true
  }.map(\.element)
}

/// The rows for one side, or all of them.
func filtered(_ items: [BrowseItem], _ filter: SideFilter) -> [BrowseItem] {
  guard filter != .both else { return items }
  let side: ChessCore.Color = filter == .w ? .w : .b
  return dropEmptyHeads(items.filter { item in
    if case .row(let row) = item { return row.side == side }
    return true
  })
}

/// Items as blocks: a new block at each heading.
func browseBlocks(_ items: [BrowseItem]) -> [BrowseBlock] {
  var blocks: [BrowseBlock] = []
  for item in items {
    switch item {
    case .head(let head): blocks.append(BrowseBlock(head: head, rows: []))
    case .row(let row):
      if blocks.isEmpty { blocks.append(BrowseBlock(head: nil, rows: [])) }
      blocks[blocks.count - 1].rows.append(row)
    }
  }
  return blocks
}

/// The lists, one card a block, each row drawn by the caller.
struct BrowseListView<Row: View>: View {
  var items: [BrowseItem]
  @ViewBuilder var row: (BrowseRow, Bool) -> Row

  var body: some View {
    if items.isEmpty {
      BrowseEmpty(text: "Nothing here yet")
    } else {
      ForEach(Array(browseBlocks(items).enumerated()), id: \.offset) { _, block in
        VStack(spacing: 0) {
          if let head = block.head { BrowseHead(text: head) }
          ForEach(Array(block.rows.enumerated()), id: \.offset) { j, item in
            if j > 0 || block.head != nil { BrowseDivider() }
            row(item, j == 0 && block.head == nil)
          }
        }
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16))
      }
    }
  }
}

struct BrowseDivider: View {
  var body: some View { Rectangle().fill(.white.opacity(0.07)).frame(height: 1) }
}

/// `.bp-head`: a list's heading.
struct BrowseHead: View {
  var text: String
  var body: some View {
    Text(text.uppercased()).font(.system(size: 12, weight: .semibold)).tracking(0.72).foregroundStyle(Theme.text2)
      .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 6)
  }
}

/// `.bp-empty`.
struct BrowseEmpty: View {
  var text: String
  var inset = false
  var body: some View {
    Text(text).font(.system(size: 14)).foregroundStyle(Theme.text3)
      .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 16).padding(.horizontal, inset ? 14 : 4)
  }
}

/// A row's side and name, with a suggestion's reason under it: `.bp-row-text`.
struct BrowseRowLabel: View {
  var row: BrowseRow
  var body: some View {
    HStack(spacing: 12) {
      SideDot(side: row.side)
      VStack(alignment: .leading, spacing: 4) {
        Text(row.label).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.text).lineLimit(1)
        if let why = row.why {
          let ink = SwiftUI.Color(hex: WHY_COLOR[why.kind] ?? 0xa3a3ad)
          Text(why.text).font(.system(size: 12, weight: .semibold)).foregroundStyle(ink).lineLimit(1)
            .padding(.horizontal, 8).padding(.vertical, 2).background(Capsule().fill(ink.opacity(0.14)))
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }
}

/// The row a tap last played out, or a row picked: tinted, with the accent down its edge.
struct RowTint: ViewModifier {
  var on: Bool
  func body(content: Content) -> some View {
    content
      .background(on ? Theme.accent.opacity(0.12) : .clear)
      .overlay(alignment: .leading) { if on { Rectangle().fill(Theme.accent).frame(width: 3) } }
  }
}

/// The trail of opened lists, and the side filter: `.bp-ctl`.
struct BrowseCrumbs: View {
  var crumbs: [String]
  var filter: Binding<SideFilter>?
  var onTap: (Int) -> Void

  var body: some View {
    HStack(spacing: 8) {
      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 2) {
          ForEach(Array(crumbs.enumerated()), id: \.offset) { i, crumb in
            if i > 0 { Text("\u{203a}").font(.system(size: 13)).foregroundStyle(Theme.text3) }
            Button { onTap(i) } label: {
              Text(crumb).font(.system(size: 13, weight: .semibold))
                .foregroundStyle(i == crumbs.count - 1 ? Theme.text : Theme.text2).padding(.vertical, 6).padding(.horizontal, 4)
            }
            .buttonStyle(.plain)
          }
        }
      }
      // Opens on the list you are in: a long trail scrolls its start out of view, not its end.
      .defaultScrollAnchor(.trailing)
      if let filter { SideFilterControl(value: filter) }
    }
    .frame(minHeight: 32)
  }
}

/// Both, W or B: `.bp-seg`.
struct SideFilterControl: View {
  @Binding var value: SideFilter

  var body: some View {
    HStack(spacing: 2) {
      ForEach([(SideFilter.both, "Both"), (.w, "W"), (.b, "B")], id: \.0) { option, label in
        Button { value = option } label: {
          Text(label).font(.system(size: 12, weight: .semibold)).foregroundStyle(value == option ? Theme.text : Theme.text2)
            .frame(minWidth: 34, minHeight: 28).padding(.horizontal, 8)
            .background(RoundedRectangle(cornerRadius: 8).fill(value == option ? Theme.surface3 : .clear))
        }
        .buttonStyle(.plain)
      }
    }
    .padding(2)
    .background(RoundedRectangle(cornerRadius: 10).fill(Theme.surface))
  }
}

/// The shelves, two to a row: `.bp-shelves`.
struct ShelvesGrid: View {
  var catalog: PickerCatalog
  var onOpen: (String, [BrowseRow]) -> Void

  var body: some View {
    LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible())], spacing: 8) {
      ForEach(SHELVES, id: \.id) { shelf in
        let rows = shelfRows(catalog, shelf)
        Button { onOpen(shelf.label, rows) } label: {
          HStack(alignment: .lastTextBaseline) {
            Text(shelf.label).font(.system(size: 15, weight: .bold)).foregroundStyle(Theme.text)
            Spacer(minLength: 4)
            Text("\(rows.count)").font(.system(size: 13)).foregroundStyle(Theme.text2)
          }
          .padding(12).frame(maxWidth: .infinity, minHeight: 64, alignment: .bottom)
          .background(Theme.surface)
          .overlay(alignment: .top) { Rectangle().fill(SwiftUI.Color(hexString: shelf.color)).frame(height: 3) }
          .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
      }
    }
  }
}

/// A list to show: `.bp-chip`.
struct BrowseChip: View {
  var label: String
  var on: Bool
  var action: () -> Void

  var body: some View {
    Button(action: action) {
      Text(label).font(.system(size: 13.5, weight: .semibold))
        .foregroundStyle(on ? SwiftUI.Color(hex: 0xb3b4ff) : Theme.text2)
        .padding(.horizontal, 13).frame(minHeight: 38)
        .background(Capsule().fill(on ? Theme.accent.opacity(0.16) : Theme.surface))
    }
    .buttonStyle(.plain)
  }
}

/// The search box: `.bp-search`.
struct BrowseSearchField: View {
  @Binding var query: String
  @FocusState private var focused: Bool

  var body: some View {
    TextField("", text: $query, prompt: Text("Name, ECO or moves").foregroundStyle(Theme.text3))
      .font(.system(size: 16)).foregroundStyle(Theme.text)
      .textInputAutocapitalization(.never).autocorrectionDisabled()
      .focused($focused)
      .padding(.horizontal, 14).padding(.vertical, 11)
      .background(RoundedRectangle(cornerRadius: 12).fill(Theme.surface))
      .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.accent, lineWidth: 1.5))
      .onAppear { focused = true }
  }
}

/// A round icon button.
struct RoundIconButton: View {
  var icon: String
  var plain = false
  var disabled = false
  var size: CGFloat = 38
  var action: () -> Void

  var body: some View {
    Button(action: action) {
      Icon(name: icon, size: 20).foregroundStyle(plain ? Theme.text2 : Theme.text)
        .frame(width: size, height: size)
        .background(Circle().fill(plain ? .clear : Theme.surface))
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .disabled(disabled).opacity(disabled ? 0.35 : 1)
  }
}
