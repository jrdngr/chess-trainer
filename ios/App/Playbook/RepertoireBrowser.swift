import Book
import ChessCore
import Model
import SwiftUI

/// One side's tree, from a node: the board, the line, the moves here, the
/// book's moves to add, and Explore. A new move played on the board
/// opens the board editor there. `RepertoireBrowser`.
struct RepertoireBrowser: View {
  let repId: String
  let startNodeId: String?
  let title: String
  let onBack: () -> Void
  let onExplore: ([String], ChessCore.Color) -> Void
  /// Open the board editor on this line.
  let onEdit: ([String]) -> Void

  @Environment(AppStore.self) private var store
  @Environment(Toasts.self) private var toasts
  @State private var nodeId: String?
  /// The line you came in on stays on the strip while you step back along it.
  @State private var lineTip: String?
  @State private var started = false
  @State private var menuFor: String?
  @State private var cutting: String?
  /// A branch chosen for deletion in the node menu; its confirm sheet opens once the menu is gone.
  @State private var cutNext: String?
  @State private var sideMenu = false

  var body: some View {
    if let rep = store.state.repertoires[repId], let index = store.index {
      content(rep, index)
    } else {
      Color.clear.onAppear(perform: onBack)
    }
  }

  @ViewBuilder private func content(_ rep: Repertoire, _ index: ReferenceIndex) -> some View {
    let at = nodeId.flatMap { rep.nodes[$0] != nil ? $0 : nil }
    let fen = fenAt(rep, at)
    let path = pathTo(rep, at)
    let pathSans = path.map(\.san)
    let full = lineTip.flatMap { rep.nodes[$0] != nil ? pathTo(rep, $0) : nil } ?? []
    let onIt = at == nil || full.contains { $0.id == at }
    let line = onIt && full.count >= path.count ? full : path
    let next = line.count > path.count ? line[path.count] : nil
    let kids = childrenOf(rep, at)
    let ourTurn = fenTurn(fen) == rep.color
    let opening = openingNameForPath(index, pathSans)
    let book = lookup(index, fen)

    VStack(spacing: 0) {
      AppBar(title: opening?.name ?? title,
             subtitle: "\(opening.map { "\($0.eco) \u{00b7} " } ?? "")\(rep.color == .w ? "as White" : "as Black")", onBack: onBack) {
        // The side's menu belongs to the whole tree, not to one line of it.
        if startNodeId == nil { IconButton(icon: "more") { sideMenu = true } }
      }
      ScrollView {
        VStack(spacing: 0) {
          BoardView(fen: fen, orientation: rep.color, interactive: true, lastMove: lastMoveOf(pathSans), bothSides: true) { move in
            onBoardMove(rep, index, kids, pathSans, move)
          }
          MoveStrip(
            items: line.enumerated().map { i, node in
              StripItem(san: node.san, label: i % 2 == 0 ? "\(i / 2 + 1)." : nil, tone: i >= path.count ? .ghost : nil,
                        current: node.id == at, seek: i + 1)
            },
            cursor: path.count, max: line.count,
            onSeek: { n in nodeId = n == 0 ? nil : line[n - 1].id }, hint: "Play a move"
          )
          .overlay(alignment: .trailing) {
            if let next { IconButton(icon: "trash", size: 18) { cutting = next.id }.padding(.trailing, 44) }
          }
          .padding(.top, 10)
          SectionHead(title: ourTurn ? "Your move" : "Replies", aside: kids.isEmpty ? nil : "\(kids.count)")
          if kids.isEmpty {
            EmptyNote(title: ourTurn ? "No move here" : "No replies", hint: "Play a move to add it")
          } else {
            ListCard {
              ForEach(kids, id: \.id) { kid in
                TreeRow(rep: rep, node: kid, card: store.state.cards[cardId(rep.id, kid.key)], ourTurn: ourTurn,
                        onOpen: { goTo(kid.id, line) }, onMenu: { menuFor = kid.id })
              }
            }
          }
          if let book, !book.moves.isEmpty {
            SectionHead(title: "The book", aside: "Tap to add")
            BookMoves(entry: book, inRepertoire: Set(kids.map(\.san))) { san in addFromBook(rep, index, pathSans, san, at) }
          }
          SheetButton("Explore", style: .soft) { onExplore(pathSans, rep.color) }
            .padding(.top, 24)
        }
        .padding(.horizontal, 16).padding(.bottom, 28)
      }
    }
    .onAppear {
      if !started {
        started = true
        nodeId = startNodeId
        lineTip = startNodeId
      }
    }
    .sheet(isPresented: $sideMenu) {
      SideMenu(repId: rep.id, onDeleted: onBack) { sideMenu = false }.presentationDetents([.medium]).presentationBackground(Theme.background)
    }
    .sheet(item: Binding(get: { menuFor.map(RepRef.init) }, set: { menuFor = $0?.id }), onDismiss: {
      if let id = cutNext { cutNext = nil; cutting = id }
    }) { ref in
      NodeMenu(rep: rep, nodeId: ref.id, onNavigate: { menuFor = nil; goTo($0, line) }, onDelete: { cutNext = $0; menuFor = nil })
        .presentationDetents([.medium, .large]).presentationBackground(Theme.background)
    }
    .sheet(item: Binding(get: { cutting.map(RepRef.init) }, set: { cutting = $0?.id })) { ref in
      cutSheet(rep, ref.id).presentationDetents([.height(260)]).presentationBackground(Theme.background)
    }
  }

  private func cutSheet(_ rep: Repertoire, _ id: String) -> some View {
    let count = subtreeIds(rep, id).count
    return VStack(alignment: .leading, spacing: 0) {
      SheetHead(title: "Delete \(count) move\(count == 1 ? "" : "s")?", moves: sansToMoveText(pathTo(rep, id).map(\.san)))
      HStack(spacing: 8) {
        SheetButton("Cancel", style: .plain) { cutting = nil }
        SheetButton("Delete", icon: "trash", style: .danger) {
          var undo: PlaybookUndo?
          store.update { undo = $0.removeNode(rep.id, id) }
          cutting = nil
          if let undo { toasts.show("Deleted \(count) move\(count == 1 ? "" : "s")", action: ("Undo", { store.update { $0.undo(undo) } })) }
        }
      }
      Spacer()
    }
    .padding(20)
  }

  private func goTo(_ id: String?, _ line: [RepMove]) {
    nodeId = id
    if let id, !line.contains(where: { $0.id == id }) { lineTip = id }
  }

  private func onBoardMove(_ rep: Repertoire, _ index: ReferenceIndex, _ kids: [RepMove], _ pathSans: [String], _ move: LegalMove) {
    if let existing = kids.first(where: { $0.san == move.san }) {
      nodeId = existing.id
      if lineTip.map({ pathTo(rep, $0).contains { $0.id == existing.id } }) != true { lineTip = existing.id }
      return
    }
    onEdit(pathSans + [move.san])
  }

  private func addFromBook(_ rep: Repertoire, _ index: ReferenceIndex, _ pathSans: [String], _ san: String, _ at: String?) {
    store.update { $0.addLine(repId, pathSans + [san], .fixed(.book)) }
    descend(san, at: at)
    toasts.show("\(san) added")
  }

  private func descend(_ san: String, at: String?) {
    guard let fresh = store.state.repertoires[repId], let child = childrenOf(fresh, at).first(where: { $0.san == san }) else { return }
    nodeId = child.id
    lineTip = child.id
  }
}

struct LineRef: Identifiable {
  var sans: [String]
  var id: String { sans.joined(separator: " ") }
}

/// The book's moves here, most played first, with what you already have marked; tap to add.
struct BookMoves: View {
  let entry: ExplorerEntry
  let inRepertoire: Set<String>
  let onPlay: (String) -> Void

  var body: some View {
    let total = max(1, entry.moves.reduce(0) { $0 + $1.games })
    ListCard {
      ForEach(entry.moves.prefix(8), id: \.san) { move in
        Button { onPlay(move.san) } label: {
          HStack(spacing: 12) {
            Text(move.san).font(.system(size: 15, weight: .bold)).foregroundStyle(inRepertoire.contains(move.san) ? Theme.accent : Theme.text)
              .frame(width: 56, alignment: .leading)
            Text("\(Int(JSRound(move.games / total * 100)))%").font(.system(size: 13).monospacedDigit()).foregroundStyle(Theme.text2)
            Spacer()
            if inRepertoire.contains(move.san) { Icon(name: "check", size: 16).foregroundStyle(Theme.accent) }
          }
          .padding(.horizontal, 16).frame(minHeight: 44).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
      }
    }
  }
}
