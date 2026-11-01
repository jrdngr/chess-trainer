import ChessCore
import Model
import Shared
import SwiftUI

/// The global selection at the top of the screens where it can be changed:
/// the square opens the side picker, the trail the opening picker. `SelectionBar`.
struct SelectionBar<Trailing: View>: View {
  @Environment(AppStore.self) private var store
  @ViewBuilder var trailing: Trailing
  @State private var picking: Picking?
  @State private var browsing = false

  enum Picking: String, Identifiable {
    case color, quick
    var id: String { rawValue }
  }

  var body: some View {
    let selection = store.state.settings.selection
    HStack(spacing: 8) {
      Button { picking = .color } label: {
        ColorSquare(choice: selection.color, size: 22).padding(.horizontal, 11).frame(minHeight: 44).background(pill)
      }
      Button { picking = .quick } label: {
        HStack(spacing: 8) {
          trail(selection.opening).frame(maxWidth: .infinity, alignment: .leading)
          Icon(name: "down", size: 16).foregroundStyle(Theme.text3)
        }
        .padding(.horizontal, 14).frame(minHeight: 44).background(pill)
      }
      trailing
    }
    .buttonStyle(.plain)
    .sheet(item: $picking) { which in
      Group {
        switch which {
        case .color: ColorPickerSheet { picking = nil }
        case .quick: QuickPicker(onClose: { picking = nil }, onBrowse: { picking = nil; browsing = true })
        }
      }
      .presentationDetents(which == .color ? [.height(300)] : [.large])
      .presentationBackground(Theme.background)
    }
    .fullScreenCover(isPresented: $browsing) {
      BrowsePicker(onClose: { browsing = false }, onBack: { browsing = false; picking = .quick })
        .background(Theme.background)
    }
  }

  private var pill: some View { RoundedRectangle(cornerRadius: 14).fill(Theme.surface) }

  @ViewBuilder private func trail(_ opening: String) -> some View {
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

/// Which side you play: `ColorPicker` in `Selection.tsx`.
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

/// A row to pick: `ChoiceRow` in `ui.tsx`.
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

/// The few picks most sessions want, one tap each: Any opening, your
/// favorites (the ones played last first), and the common first moves. `QuickPicker`.
struct QuickPicker: View {
  @Environment(AppStore.self) private var store
  let onClose: () -> Void
  var onBrowse: () -> Void = {}
  @State private var showAll = false

  static let firstMoves = ["e4", "d4", "c4", "Nf3"]
  static let favoritesShown = 6

  var body: some View {
    let state = store.state
    let selection = state.settings.selection
    let mine = favorites
    ScrollView {
      VStack(alignment: .leading, spacing: 14) {
        Text("Opening").font(.system(size: 22, weight: .heavy)).foregroundStyle(Theme.text)
        SegmentedControl(
          value: Binding(get: { selection.color }, set: { c in store.update { $0.settings.selection.color = c } }),
          options: [ColorChoice.w, .b, .random].map { ($0, colorLabel($0)) })
        tile("Any opening", chosen: selection.opening == "") { choose("", nil) }
        if !mine.isEmpty {
          tile("Any favorite", chosen: selection.opening == ANY_FAVORITE) { choose(ANY_FAVORITE, nil) }
          section("Favorites")
          LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible())], spacing: 8) {
            ForEach(showAll ? mine : Array(mine.prefix(Self.favoritesShown)), id: \.node.id) { fav in
              let stats = state.score.nodes[fav.node.id]
              Button { choose(fav.node.id, fav.side) } label: {
                VStack(alignment: .leading, spacing: 6) {
                  HStack(spacing: 7) {
                    SideDot(side: fav.side)
                    Text(fav.label).font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.text).lineLimit(1)
                  }
                  TierBar(rating: stats?.rating ?? 0, rated: stats?.rated ?? 0)
                }
                .padding(.horizontal, 12).padding(.vertical, 10).frame(maxWidth: .infinity, alignment: .leading)
                .background(tileBackground(selection.opening == fav.node.id))
              }
              .buttonStyle(.plain)
            }
          }
          if mine.count > Self.favoritesShown {
            Button { showAll.toggle() } label: {
              Text(showAll ? "Show fewer" : "Show all \(mine.count)")
                .font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.text2).frame(maxWidth: .infinity).padding(10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
          }
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

  /// Your favorites, played last first, each with the side it is played from and its short name.
  private var favorites: [(node: OpeningNode, side: ChessCore.Color, label: String)] {
    guard let tree = store.tree, let catalog = store.catalog else { return [] }
    let lastAt = { (id: String) in store.state.score.nodes[id]?.lastAt ?? 0 }
    return store.state.settings.favoriteOpenings.compactMap { tree.byId[$0] }.filter { $0.depth > 0 }
      .jsSorted { cmp(lastAt($1.id), lastAt($0.id)) }
      .map { ($0, sideForPick(catalog, $0) ?? .w, favoriteLabel(catalog, $0)) }
  }

  private func choose(_ opening: String, _ side: ChessCore.Color?) {
    store.update {
      $0.settings.selection.opening = opening
      if let side { $0.settings.selection.color = side == .w ? .w : .b }
    }
    onClose()
  }

  private func tile(_ name: String, chosen: Bool, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Text(name).font(.system(size: 16, weight: .bold)).foregroundStyle(Theme.text)
        .frame(maxWidth: .infinity, alignment: .leading).padding(14).background(tileBackground(chosen))
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

/// A favorite's name as the picker shows it, short where the book's is long.
func favoriteLabel(_ catalog: PickerCatalog, _ node: OpeningNode) -> String {
  shortLabel(entryForNode(catalog, node)?.label ?? node.name)
}

/// "1.e4 e5 2.Nf3": a line numbered from the start.
func moveText(_ sans: [String]) -> String {
  sans.enumerated().map { i, san in i % 2 == 0 ? "\(i / 2 + 1).\(san)" : san }.joined(separator: " ")
}

/// A line written as moves separated by spaces.
func line(_ text: String) -> [String] { text.isEmpty ? [] : text.split(separator: " ").map(String.init) }
