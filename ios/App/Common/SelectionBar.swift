import ChessCore
import Model
import Shared
import SwiftUI

/// The global selection at the top of the screens where it can be changed:
/// the square opens the side picker, the trail the opening picker. `SelectionBar`.
struct SelectionBar<Trailing: View>: View {
  @Environment(AppStore.self) private var store
  @ViewBuilder var trailing: Trailing
  @State private var picking: SelectionPicking?

  var body: some View {
    let selection = store.state.settings.selection
    HStack(spacing: 8) {
      Button { picking = .color } label: {
        ColorSquare(choice: selection.color, size: 22).padding(.horizontal, 11).frame(minHeight: 44).background(pill)
      }
      Button { picking = .quick } label: {
        HStack(spacing: 8) {
          SelectionTrail(opening: selection.opening).frame(maxWidth: .infinity, alignment: .leading)
          Icon(name: "down", size: 16).foregroundStyle(Theme.text3)
        }
        .padding(.horizontal, 14).frame(minHeight: 44).background(pill)
      }
      trailing
    }
    .buttonStyle(.plain)
    .selectionSheets($picking)
  }

  private var pill: some View { RoundedRectangle(cornerRadius: 14).fill(Theme.surface) }
}

/// Which selection sheet is open: the side or the quick opening picker.
enum SelectionPicking: String, Identifiable {
  case color, quick
  var id: String { rawValue }
}

/// The side sheet, the quick opening sheet and, from it, Browse all openings, for whatever opens them.
struct SelectionSheets: ViewModifier {
  @Binding var picking: SelectionPicking?
  @State private var browsing = false
  /// The presentation to open once the current one is dismissed.
  @State private var next: Next?

  enum Next { case browse, quick }

  func body(content: Content) -> some View {
    content
      .sheet(item: $picking, onDismiss: {
        if next == .browse { next = nil; browsing = true }
      }) { which in
        Group {
          switch which {
          case .color: ColorPickerSheet { picking = nil }
          case .quick: QuickPicker(onClose: { picking = nil }, onBrowse: { next = .browse; picking = nil })
          }
        }
        .presentationDetents(which == .color ? [.height(300)] : [.large])
        .presentationBackground(Theme.background)
      }
      .fullScreenCover(isPresented: $browsing, onDismiss: {
        if next == .quick { next = nil; picking = .quick }
      }) {
        BrowsePicker(onClose: { browsing = false }, onBack: { next = .quick; browsing = false })
          .background(Theme.background)
      }
  }
}

extension View {
  func selectionSheets(_ picking: Binding<SelectionPicking?>) -> some View { modifier(SelectionSheets(picking: picking)) }
}

/// The selected opening as short names from its family down, the last one brightest.
struct SelectionTrail: View {
  @Environment(AppStore.self) private var store
  let opening: String

  var body: some View {
    if let tree = store.tree, let catalog = store.catalog {
      let parts = selectionTrail(tree, catalog, opening)
      HStack(spacing: 0) {
        ForEach(Array(parts.enumerated()), id: \.offset) { i, label in
          if i > 0 { Text("\u{203a}").foregroundStyle(Theme.text3).padding(.horizontal, 5) }
          Text(label).foregroundStyle(i == parts.count - 1 ? Theme.text : Theme.text2)
            .layoutPriority(i == parts.count - 1 ? 1 : 0)
        }
      }
      .font(.system(size: 15, weight: .semibold)).lineLimit(1)
    }
  }
}

extension SelectionBar where Trailing == EmptyView {
  init() { self.init { EmptyView() } }
}

/// Which side you play.
struct ColorPickerSheet: View {
  @Environment(AppStore.self) private var store
  let onClose: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      Text("Play as").font(.system(size: 22, weight: .heavy)).foregroundStyle(Theme.text)
      VStack(spacing: 0) {
        ForEach([ColorChoice.w, .b, .random], id: \.self) { choice in
          Button {
            store.update { $0.settings.selection.color = choice }
            onClose()
          } label: {
            ChoiceRow(title: colorLabel(choice), meta: choice == .random ? "A coin flip each game" : nil,
                      selected: store.state.settings.selection.color == choice) { ColorSquare(choice: choice, size: 22) }
          }
          .buttonStyle(.plain)
        }
      }
      .background(RoundedRectangle(cornerRadius: 18).fill(Theme.surface))
    }
    .padding(20)
  }
}

/// A row to pick.
struct ChoiceRow<Leading: View>: View {
  var title: String
  var meta: String?
  var selected: Bool
  @ViewBuilder var leading: Leading

  var body: some View {
    HStack(spacing: 12) {
      leading
      VStack(alignment: .leading, spacing: 2) {
        Text(title).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.text)
        if let meta { Text(meta).font(.system(size: 12.5)).foregroundStyle(Theme.text3) }
      }
      Spacer()
      if selected { Icon(name: "check", size: 18).foregroundStyle(Theme.accent) }
    }
    .padding(.horizontal, 16).frame(minHeight: 54).contentShape(Rectangle())
  }
}

/// The few picks most sessions want, one tap each: Any Opening, your
/// openings (most worth focusing on first), openings you picked lately, and
/// the common first moves. White and Black list that side's openings, Random both
/// in a column each. Recent's More opens the whole history in place. `QuickPicker`.
struct QuickPicker: View {
  @Environment(AppStore.self) private var store
  let onClose: () -> Void
  var onBrowse: () -> Void = {}
  @State private var showAll = false
  /// The full Recent list, over the sheet's page.
  @State private var history = false

  static let firstMoves = ["e4", "d4", "c4", "Nf3"]
  /// Your openings shown before More: six on a side's tab, four a column on Random.
  private func shownCount(_ side: ChessCore.Color?) -> Int { side == nil ? 8 : 6 }

  var body: some View {
    if history {
      RecentHistory(onBack: { history = false }, onPick: { choose($0.opening, nil, color: $0.color) })
    } else {
      quick
    }
  }

  private var quick: some View {
    let state = store.state
    let selection = state.settings.selection
    let mine = store.yourOpenings()
    let recent = recentTiles
    return ScrollView {
      VStack(alignment: .leading, spacing: 14) {
        Text("Opening").font(.system(size: 22, weight: .heavy)).foregroundStyle(Theme.text)
        SegmentedControl(
          value: Binding(get: { selection.color }, set: { c in store.update { $0.settings.selection.color = c } }),
          options: [ColorChoice.w, .b, .random].map { ($0, colorLabel($0)) })
        tile("Any Opening", chosen: selection.opening == ANY_OPENING) { choose(ANY_OPENING, nil, color: .random) }
        let side = shownSide(selection)
        let yours = mine.filter { side == nil || $0.side == side }
        if !yours.isEmpty {
          section("Your openings")
          sided(yours, side: side, limit: showAll ? nil : shownCount(side)) { opening in
            openingTile(opening.node.id, shortLabel(opening.name), chosen: chosen(opening, selection)) {
              choose(opening.node.id, opening.side)
            }
            // The tutorial's step after its fourth game: pick the answer to 1.d4. Above the
            // row, pointing down, so the rows and sections after it can't cover it.
            .tip(text: d4Step && opening.side == .b && opening.node.sans.first == "d4" ? D4_ROW_TIP : nil, arrow: .down)
          }
          if !showAll && overflows(yours, side: side, limit: shownCount(side)) {
            more { showAll = true }
          }
        }
        let recentShown = recent.filter { side == nil || $0.side == side }
        if !recentShown.isEmpty {
          section("Recent")
          sided(recentShown, side: side, limit: nil) { item in
            openingTile(item.pick.opening, item.label, chosen: selection.opening == item.pick.opening) {
              choose(item.pick.opening, nil, color: item.pick.color)
            }
          }
          if state.recent.count > recentShown.count { more { history = true } }
        }
        section("First move")
        HStack(spacing: 8) {
          ForEach(Self.firstMoves, id: \.self) { id in
            Button { choose(id, nil) } label: {
              Text(moveText(line(id))).font(.system(size: 15, weight: .bold, design: .monospaced)).foregroundStyle(Theme.text)
                .frame(maxWidth: .infinity).padding(.vertical, 12).background(tileBackground(selection.opening == id))
            }
            .buttonStyle(.plain)
          }
        }
        Button(action: onBrowse) {
          HStack {
            Text("Browse all openings").font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.text)
            Spacer()
            Icon(name: "chevron", size: 16).foregroundStyle(Theme.text3)
          }
          .padding(.horizontal, 14).frame(height: 48).background(RoundedRectangle(cornerRadius: 14).fill(Theme.surface2))
        }
        .buttonStyle(.plain)
      }
      .padding(20)
    }
  }

  /// The tutorial's step after its fourth game.
  private var d4Step: Bool { store.state.settings.tutorial?.played == 4 }

  /// One of your openings is chosen when the selection is its node, from its side.
  private func chosen(_ opening: YourOpening, _ selection: Selection) -> Bool {
    selection.opening == opening.node.id && selection.color == (opening.side == .w ? .w : .b)
  }

  /// The Recent tiles: your newest picks, less your openings and the first moves, which have tiles of their own.
  private var recentTiles: [RecentTile] {
    guard let tree = store.tree, let catalog = store.catalog else { return [] }
    let skip = Set(store.yourOpenings().map(\.node.id) + Self.firstMoves)
    return quickRecent(store.state.recent.filter { tree.byId[$0.opening] != nil }, skipping: skip).map { pick in
      let node = tree.byId[pick.opening]!
      return RecentTile(pick: pick, side: recentSide(pick, catalog, node), label: openingLabel(catalog, node))
    }
  }

  private func choose(_ opening: String, _ side: ChessCore.Color?, color: ColorChoice? = nil) {
    store.update {
      $0.settings.selection.opening = opening
      if let side { $0.settings.selection.color = side == .w ? .w : .b }
      if let color { $0.settings.selection.color = color }
    }
    onClose()
  }

  /// An opening's tile: its name and its rating bar. The column or tab says its side.
  private func openingTile(_ id: String, _ label: String, chosen: Bool, action: @escaping () -> Void) -> some View {
    let stats = store.state.score.nodes[id]
    return Button(action: action) {
      VStack(alignment: .leading, spacing: 6) {
        Text(label).font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.text).lineLimit(1)
        TierBar(rating: stats?.rating ?? 0, rated: stats?.rated ?? 0, label: false)
      }
      .padding(.horizontal, 12).padding(.vertical, 10).frame(maxWidth: .infinity, alignment: .leading)
      .background(tileBackground(chosen))
    }
    .buttonStyle(.plain)
  }

  /// The side the tab lists, or nil for both: Random, and the tutorial's step that needs a Black row.
  private func shownSide(_ selection: Selection) -> ChessCore.Color? {
    if d4Step { return nil }
    switch selection.color {
    case .w: return .w
    case .b: return .b
    case .random: return nil
    }
  }

  /// Tiles two to a row for one side, or a White column beside a Black column for both.
  @ViewBuilder private func sided<Item: Sided, Tile: View>(
    _ items: [Item], side: ChessCore.Color?, limit: Int?, @ViewBuilder tile: @escaping (Item) -> Tile
  ) -> some View {
    if side != nil {
      LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible())], spacing: 8) {
        ForEach(Array(items.prefix(limit ?? items.count).enumerated()), id: \.offset) { _, item in tile(item) }
      }
    } else {
      HStack(alignment: .top, spacing: 8) {
        ForEach([ChessCore.Color.w, .b], id: \.self) { color in
          let column = items.filter { $0.side == color }
          VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
              SideDot(side: color)
              Text(color == .w ? "White" : "Black").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.text2)
            }
            .padding(.horizontal, 4)
            ForEach(Array(column.prefix((limit ?? 2 * column.count) / 2).enumerated()), id: \.offset) { _, item in tile(item) }
          }
          .frame(maxWidth: .infinity, alignment: .topLeading)
        }
      }
    }
  }

  /// More tiles than `sided` shows at `limit`.
  private func overflows<Item: Sided>(_ items: [Item], side: ChessCore.Color?, limit: Int) -> Bool {
    if side != nil { return items.count > limit }
    return [ChessCore.Color.w, .b].contains { color in items.filter { $0.side == color }.count > limit / 2 }
  }

  private func more(_ action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Text("More\u{2026}")
        .font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.text2).frame(maxWidth: .infinity).padding(10)
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }

  private func tile(_ name: String, chosen: Bool, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Text(name).font(.system(size: 15, weight: .bold)).foregroundStyle(Theme.text).lineLimit(1)
        .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 14).frame(minHeight: 50)
        .background(tileBackground(chosen))
    }
    .buttonStyle(.plain)
  }

  private func tileBackground(_ chosen: Bool) -> some View {
    RoundedRectangle(cornerRadius: 14).fill(Theme.surface2)
      .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(chosen ? Theme.accent : .clear, lineWidth: 2))
  }

  private func section(_ title: String) -> some View {
    Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.text2).padding(.horizontal, 4)
  }
}

/// A tile's side, for `QuickPicker.sided`.
private protocol Sided { var side: ChessCore.Color { get } }
extension YourOpening: Sided {}
private struct RecentTile: Sided {
  var pick: RecentPick
  var side: ChessCore.Color
  var label: String
}

/// An opening's name as the picker shows it, short where the book's is long.
func openingLabel(_ catalog: PickerCatalog, _ node: OpeningNode) -> String {
  shortLabel(entryForNode(catalog, node)?.label ?? node.name)
}

/// "1.e4 e5 2.Nf3": a line numbered from the start.
func moveText(_ sans: [String]) -> String {
  sans.enumerated().map { i, san in i % 2 == 0 ? "\(i / 2 + 1).\(san)" : san }.joined(separator: " ")
}

/// A line written as moves separated by spaces.
func line(_ text: String) -> [String] { text.isEmpty ? [] : text.split(separator: " ").map(String.init) }

/// The side a recent pick shows: the one it was played as, or the opening's own under Random.
func recentSide(_ pick: RecentPick, _ catalog: PickerCatalog, _ node: OpeningNode) -> ChessCore.Color {
  switch pick.color {
  case .w: .w
  case .b: .b
  case .random: sideForPick(catalog, node) ?? .w
  }
}

/// Every opening you picked and played, newest first, under Today, Yesterday,
/// This week and then the month. Tap one to select it.
struct RecentHistory: View {
  @Environment(AppStore.self) private var store
  let onBack: () -> Void
  let onPick: (RecentPick) -> Void

  var body: some View {
    let state = store.state
    VStack(spacing: 0) {
      HStack(spacing: 8) {
        IconButton(icon: "back", plain: true, action: onBack).accessibilityLabel("Back")
        Text("Recent").font(.system(size: 22, weight: .heavy)).foregroundStyle(Theme.text)
        Spacer()
      }
      .padding(.horizontal, 10).padding(.top, 14)
      ScrollView {
        VStack(alignment: .leading, spacing: 6) {
          if let tree = store.tree, let catalog = store.catalog {
            let picks = state.recent.filter { tree.byId[$0.opening] != nil }
            ForEach(recentGroups(picks, now: Env.now()), id: \.label) { group in
              Text(group.label).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.text2)
                .padding(.horizontal, 4).padding(.top, 10)
              VStack(spacing: 0) {
                ForEach(group.picks, id: \.opening) { pick in
                  row(pick, tree.byId[pick.opening]!, catalog, chosen: state.settings.selection.opening == pick.opening)
                }
              }
              .background(RoundedRectangle(cornerRadius: 14).fill(Theme.surface2))
            }
          }
        }
        .padding(.horizontal, 20).padding(.bottom, 20)
      }
    }
  }

  private func row(_ pick: RecentPick, _ node: OpeningNode, _ catalog: PickerCatalog, chosen: Bool) -> some View {
    let stats = store.state.score.nodes[pick.opening]
    return Button { onPick(pick) } label: {
      HStack(spacing: 10) {
        SideDot(side: recentSide(pick, catalog, node))
        Text(openingLabel(catalog, node)).font(.system(size: 15, weight: .semibold))
          .foregroundStyle(chosen ? Theme.accent : Theme.text).lineLimit(1)
        Spacer(minLength: 4)
        TierBar(rating: stats?.rating ?? 0, rated: stats?.rated ?? 0).frame(width: 96)
      }
      .padding(.horizontal, 14).frame(minHeight: 50).contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }
}
