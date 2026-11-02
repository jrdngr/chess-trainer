import Book
import ChessCore
import Model
import SwiftUI

/// Picking openings by name: the book's families, suggestions and shelves as
/// lists, with no board, since playing the moves in is Play on the board.
///
/// Tapping a row picks that opening, its own moves and no more, and tapping it
/// again drops it; › opens what is under it. Picked lists everything held so
/// far, from any path, to drop. Suggestions read the Playbook as the picks
/// would make it, and leave out the picks and the lines inside them.
struct PickOpeningsView: View {
  let tree: OpeningTree
  let index: ReferenceIndex
  @Binding var picked: [PendingOpening]
  let listed: [String]
  let onBack: () -> Void
  let onAdd: () -> Void

  @Environment(AppStore.self) private var store
  @State private var chip: PickChip = .book
  @State private var trail: [BrowseLevel] = []
  @State private var filter: SideFilter = .both
  @State private var searching = false
  @State private var query = ""
  @State private var repsMemo = Memo<[Repertoire]>()
  @State private var rootMemo = Memo<[BrowseItem]>()

  var body: some View {
    let added = picked.filter { !listed.contains($0.key) }.count
    VStack(spacing: 0) {
      OnbAppBar(title: "Pick openings", onBack: onBack) {
        RoundIconButton(icon: "search") {
          searching.toggle()
          query = ""
        }
      }
      VStack(spacing: 10) {
        if searching { BrowseSearchField(query: $query) } else { chips }
        ScrollViewReader { proxy in
          ScrollView {
            VStack(spacing: 10) {
              Color.clear.frame(height: 0).id("top")
              pane
            }
            .padding(.bottom, 20)
          }
          .onChange(of: trail.count) { proxy.scrollTo("top", anchor: .top) }
        }
      }
      .padding(.horizontal, 16).padding(.top, 4)
      OnboardBar {
        BigButton(
          label: added > 0 ? "Add \(plural(added, "opening"))" : listed.isEmpty ? "Add openings" : "Done",
          accent: !picked.isEmpty, disabled: picked.isEmpty, action: onAdd)
      }
    }
    .onAppear(perform: debugOpen)
    // The Picked chip goes when its list empties, so the default chip takes over.
    .onChange(of: picked.isEmpty) { if picked.isEmpty && chip == .picked { pickChip(.book) } }
  }

  /// Debug builds open `PICK_CHIP=book|suggest|shelves|picked`, and with `PICK_OPEN=1` the first row's list, for screenshots.
  private func debugOpen() {
    #if DEBUG
      let env = ProcessInfo.processInfo.environment
      if let raw = env["PICK_CHIP"], let c = [PickChip.book, .suggest, .shelves, .picked].first(where: { "\($0)" == raw }) { chip = c }
      if env["PICK_OPEN"] == "1", let catalog = store.catalog,
        let row = rootItems(catalog).compactMap({ if case .row(let r) = $0, r.open != nil { r } else { nil } }).first {
        trail = [BrowseLevel(label: row.label, items: row.open!())]
      }
    #endif
  }

  private var chips: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: 6) {
        if !picked.isEmpty { BrowseChip(label: "Picked (\(picked.count))", on: chip == .picked) { pickChip(.picked) } }
        ForEach([PickChip.book, .suggest, .shelves], id: \.self) { c in BrowseChip(label: c.label, on: chip == c) { pickChip(c) } }
      }
      .padding(.horizontal, 16)
    }
    .padding(.horizontal, -16)
  }

  @ViewBuilder private var pane: some View {
    if searching {
      if !query.trimmingCharacters(in: .whitespaces).isEmpty, let catalog = store.catalog {
        BrowseListView(items: filtered(searchItems(query, reps, index, tree, catalog), filter)) { row, _ in rowView(row) }
      }
    } else if chip == .picked {
      PickedList(picked: $picked)
    } else if let catalog = store.catalog {
      let items = trail.last?.items ?? (chip == .shelves ? nil : rootItems(catalog))
      BrowseCrumbs(crumbs: [chip.label] + trail.map(\.label), filter: items == nil ? nil : $filter) { trail = Array(trail.prefix($0)) }
      if let items {
        BrowseListView(items: filtered(items, filter)) { row, _ in rowView(row) }
      } else {
        ShelvesGrid(catalog: catalog) { label, rows in trail = [BrowseLevel(label: label, items: rows.map { .row($0) })] }
      }
    }
  }

  private func rowView(_ row: BrowseRow) -> some View {
    let on = picked.contains { $0.key == row.sans.joined(separator: " ") }
    return HStack(spacing: 0) {
      Button { toggle(row) } label: {
        HStack(spacing: 12) {
          BrowseRowLabel(row: row)
          Group { if on { Icon(name: "check", size: 16).foregroundStyle(Theme.accent) } }.frame(width: 18)
        }
        .padding(.leading, 14).padding(.trailing, 6).padding(.vertical, 8).frame(minHeight: 56).contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      if let open = row.open {
        Button { trail.append(BrowseLevel(label: row.label, items: open())) } label: {
          Icon(name: "chevron", size: 18).foregroundStyle(Theme.text3).frame(width: 44).frame(maxHeight: .infinity).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .leading) { Rectangle().fill(.white.opacity(0.07)).frame(width: 1) }
      }
    }
    .fixedSize(horizontal: false, vertical: true)
    .modifier(RowTint(on: on))
  }

  /// The Playbook as the picks would make it, for suggestions and search.
  private var reps: [Repertoire] {
    repsMemo.get(pendingKey(picked)) { onboardedState(store.state, tree, picked).repertoireList }
  }

  private func rootItems(_ catalog: PickerCatalog) -> [BrowseItem] {
    rootMemo.get("\(chip) \(pendingKey(picked))") {
      if chip == .book { return bookItems(catalog) }
      // Growing an opening you picked is not picking another one.
      let inside = { (row: BrowseRow) in
        picked.contains { pick in
          pick.color == row.side && pick.sans.count <= row.sans.count && zip(pick.sans, row.sans).allSatisfy { $0 == $1 }
        }
      }
      return suggestions(reps, index, tree, catalog).filter { !inside($0) }.map { .row($0) }
    }
  }

  private func toggle(_ row: BrowseRow) {
    let key = row.sans.joined(separator: " ")
    if picked.contains(where: { $0.key == key }) {
      picked.removeAll { $0.key == key }
      return
    }
    let seed = seedFor(row.sans, row.side)
    let name = tree.byId[key].map { shortLabel($0.name) } ?? row.label
    picked.append(PendingOpening(key: key, name: name, color: seed.color, moves: countOwnMoves([(sans: seed.sans, color: seed.color)]), sans: row.sans))
  }

  private func pickChip(_ next: PickChip) {
    chip = next
    trail = []
    searching = false
    query = ""
  }
}

enum PickChip: Hashable {
  case picked, book, suggest, shelves

  var label: String {
    switch self {
    case .picked: "Picked"
    case .book: "Book"
    case .suggest: "Suggestions"
    case .shelves: "Shelves"
    }
  }
}

/// Everything held so far, from any path, each with a button to drop it.
struct PickedList: View {
  @Binding var picked: [PendingOpening]

  var body: some View {
    if picked.isEmpty {
      BrowseEmpty(text: "Nothing picked yet")
    } else {
      ListCard {
        ForEach(picked, id: \.key) { pick in
          HStack(spacing: 12) {
            SideSquare(color: pick.color)
            Text(pick.name).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.text).frame(maxWidth: .infinity, alignment: .leading)
            RoundIconButton(icon: "close") { picked.removeAll { $0.key == pick.key } }
          }
          .padding(.horizontal, 16).padding(.vertical, 10).frame(minHeight: 54)
        }
      }
    }
  }
}
