import Book
import ChessCore
import Model
import SwiftUI

/// One opening of the Playbook: its board and rating, Select,
/// Middlegame and Grow, and its lines, each opening in the tree. Its menu deletes it.
struct OpeningPage: View {
  let tree: OpeningTree
  let index: ReferenceIndex
  let repId: String
  let name: String
  let onBack: () -> Void
  /// Open the tree at a line's last move, under a title.
  let onOpenLine: (String, String) -> Void
  let onGrow: (GrowOffer) -> Void
  let onMiddlegame: (ChessCore.Color, [String]) -> Void
  /// The opening is now the global selection.
  let onSelected: () -> Void

  @Environment(AppStore.self) private var store
  @Environment(Toasts.self) private var toasts
  @State private var deleting = false

  var body: some View {
    if let rep = store.state.repertoires[repId], let row = playbookRows(rep, index).first(where: { $0.name == name }) {
      content(rep, row)
    } else {
      Color.clear.onAppear(perform: onBack)
    }
  }

  private func content(_ rep: Repertoire, _ row: PlaybookRow) -> some View {
    let lines = linesOf(rep, row, index)
    let node = openingNode(tree, row)
    let stats = node.map { nodeStats(store.state.score, $0.id) } ?? NodeStats()
    let removes = row.parts.reduce(0) { $0 + $1.removes }
    return VStack(spacing: 0) {
      AppBar(title: "", onBack: onBack) {
        Menu {
          Button(role: .destructive) { deleting = true } label: { Label("Delete opening", systemImage: "trash") }
        } label: {
          Icon(name: "more", size: 20).foregroundStyle(Theme.text).frame(width: 38, height: 38).background(Circle().fill(Theme.surface))
        }
        .accessibilityLabel("More")
      }
      ScrollView {
        VStack(spacing: 0) {
          hero(row, stats)
          VStack(spacing: 8) {
            SheetButton("Select", icon: "check", style: .accent) { select(rep, node) }
              .disabled(node == nil)
            HStack(spacing: 8) {
              SheetButton("Middlegame", icon: "middlegame", style: .plain) {
                if let main = lines.first { onMiddlegame(rep.color, main.path) }
              }
              .disabled(lines.isEmpty)
              SheetButton("Grow", icon: "sprout", style: .plain) { grow(rep, node) }
            }
          }
          .padding(.top, 12)
          HStack {
            Text("LINES").frame(maxWidth: .infinity, alignment: .leading)
            Text("MOVES").frame(width: 56, alignment: .trailing)
            Spacer().frame(width: 18)
          }
          .font(.system(size: 11.5, weight: .semibold)).tracking(0.6).foregroundStyle(Theme.text3)
          .padding(.horizontal, 16).padding(.top, 20).padding(.bottom, 6)
          ListCard {
            ForEach(lines, id: \.tipId) { line in lineRow(rep, row, line) }
          }
        }
        .padding(.horizontal, 16).padding(.bottom, 28)
      }
    }
    .confirmationDialog("Delete \(row.name)?", isPresented: $deleting, titleVisibility: .visible) {
      Button("Delete \(removes) \(removes == 1 ? "move" : "moves")", role: .destructive) {
        store.update { state in
          for part in row.parts {
            state.removeOpening(rep.id, part.rootId, tips: part.nested != nil ? tipsOf(rep, part) : nil)
          }
        }
        toasts.show("\(row.name) deleted")
        onBack()
      }
    }
  }

  private func hero(_ row: PlaybookRow, _ stats: NodeStats) -> some View {
    HStack(spacing: 14) {
      MiniBoard(sans: row.parts.first?.path ?? [], orientation: row.color, size: 116, lastMove: true)
        .clipShape(RoundedRectangle(cornerRadius: 6))
      VStack(alignment: .leading, spacing: 0) {
        Text(row.name).font(.system(size: 20, weight: .heavy)).foregroundStyle(Theme.text).lineLimit(2)
        Text(stats.rated == 0 ? "\u{2014}" : ratingText(stats.rating))
          .font(.system(size: 38, weight: .heavy).monospacedDigit()).tracking(-1.2).foregroundStyle(Theme.text).padding(.top, 8)
        TierBar(rating: stats.rating, rated: stats.rated)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .padding(16).background(RoundedRectangle(cornerRadius: 22).fill(Theme.surface))
  }

  private func lineRow(_ rep: Repertoire, _ row: PlaybookRow, _ line: OpeningLine) -> some View {
    Button { onOpenLine(line.tipId, row.name) } label: {
      HStack(spacing: 6) {
        Text(line.name).foregroundStyle(Theme.text2).lineLimit(1)
        if let split = line.split { Text(split).fontWeight(.bold).foregroundStyle(Theme.text).fixedSize() }
        Spacer(minLength: 8)
        Text("\((line.path.count + 1) / 2)").fontWeight(.bold).monospacedDigit().foregroundStyle(Theme.text)
          .frame(width: 56, alignment: .trailing)
        Icon(name: "chevron", size: 18).foregroundStyle(Theme.text3)
      }
      .font(.system(size: 15)).padding(.horizontal, 16).frame(minHeight: 52).contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .contextMenu {
      Button { onMiddlegame(rep.color, line.path) } label: { Label("Play to a middlegame", systemImage: "arrow.forward") }
      Button(role: .destructive) { deleteLine(rep, line) } label: { Label("Delete line", systemImage: "trash") }
    }
  }

  private func deleteLine(_ rep: Repertoire, _ line: OpeningLine) {
    var undo: PlaybookUndo?
    store.update { undo = $0.removeLine(rep.id, line.tipId) }
    if let undo {
      toasts.show("Deleted \(line.removes) move\(line.removes == 1 ? "" : "s")", action: ("Undo", { store.update { $0.undo(undo) } }))
    }
  }

  /// Make this opening and its side the global selection, as the opening picker does.
  private func select(_ rep: Repertoire, _ node: OpeningNode?) {
    guard let node else { return }
    store.update {
      $0.settings.selection.opening = node.id
      $0.settings.selection.color = rep.color == .w ? .w : .b
    }
    onSelected()
  }

  /// Growth's own pick for this opening, past Growth's settings when there is none within.
  private func grow(_ rep: Repertoire, _ node: OpeningNode?) {
    let prefs = store.state.settings.growth
    guard let node,
      let launch = growLaunch(
        rep, index, tree, node, minShare: prefs.minShare, maxPly: prefs.maxPly, starred: store.state.settings.favoriteOpenings)
    else {
      toasts.show("Nothing to grow here")
      return
    }
    onGrow(GrowOffer(kind: "opening", text: nil, launch: launch))
  }
}
