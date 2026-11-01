import Book
import ChessCore
import Model
import SwiftUI

/// One side's tree, from a node: the board, the line, the moves here, the
/// book's moves to add, and Explore and Drill. `RepertoireBrowser`.
struct RepertoireBrowser: View {
  let repId: String
  let startNodeId: String?
  let title: String
  let onBack: () -> Void
  let onExplore: ([String], ChessCore.Color) -> Void
  let onDrill: (String, String, String) -> Void

  @Environment(AppStore.self) private var store
  @Environment(Toasts.self) private var toasts
  @State private var nodeId: String?
  /// The line you came in on stays on the strip while you step back along it.
  @State private var lineTip: String?
  @State private var started = false
  @State private var pending: LegalMove?
  @State private var menuFor: String?
  @State private var cutting: String?
  @State private var sideMenu = false
  @State private var saving: [String]?
  @State private var savingSource = MoveSource.manual

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
    let kinds = treeKinds(rep, index)
    let ourTurn = fenTurn(fen) == rep.color
    let opening = openingNameForPath(index, pathSans)
    let book = lookup(index, fen)

    VStack(spacing: 0) {
      AppBar(title: opening?.name ?? title,
             subtitle: "\(opening.map { "\($0.eco) \u{00b7} " } ?? "")\(rep.color == .w ? "as White" : "as Black")", onBack: onBack) {
        IconButton(icon: "more") { sideMenu = true }
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
          if let pending {
            HStack {
              VStack(alignment: .leading, spacing: 2) {
                Text("Add \(pending.san)?").font(.system(size: 15, weight: .bold)).foregroundStyle(Theme.text)
                Text(ourTurn ? "Your move" : "Opponent reply").font(.system(size: 12)).foregroundStyle(Theme.text3)
              }
              Spacer()
              Button("Cancel") { self.pending = nil }.buttonStyle(PlayButtonStyle(height: 38, radius: 11, font: 14))
              Button("Add") { commit(rep, pathSans, pending) }.buttonStyle(PlayButtonStyle(kind: .primary, height: 38, radius: 11, font: 14))
            }
            .padding(14).background(RoundedRectangle(cornerRadius: 18).fill(Theme.accent.opacity(0.14))).padding(.top, 8)
          }
          SectionHead(title: ourTurn ? "Your move" : "Replies", aside: kids.isEmpty ? nil : "\(kids.count)")
          if kids.isEmpty {
            EmptyNote(title: ourTurn ? "No move here" : "No replies", hint: "Play a move to add it")
          } else {
            ListCard {
              ForEach(kids, id: \.id) { kid in
                TreeRow(rep: rep, node: kid, kind: kinds[kid.id], card: store.state.cards[cardId(rep.id, kid.key)], ourTurn: ourTurn,
                        onOpen: { goTo(kid.id, line) }, onMenu: { menuFor = kid.id })
              }
            }
          }
          if let book, !book.moves.isEmpty {
            SectionHead(title: "The book", aside: "Tap to add")
            BookMoves(entry: book, inRepertoire: Set(kids.map(\.san))) { san in addFromBook(rep, index, pathSans, san, at) }
          }
          HStack(spacing: 8) {
            SheetButton("Explore", style: .soft) { onExplore(pathSans, rep.color) }
            SheetButton("Drill", icon: "home", style: .primary) {
              onDrill(rep.id, at ?? childrenOf(rep, nil).first?.id ?? "", opening?.name ?? title)
            }
          }
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
    .sheet(item: Binding(get: { menuFor.map(RepRef.init) }, set: { menuFor = $0?.id })) { ref in
      NodeMenu(rep: rep, nodeId: ref.id, onNavigate: { menuFor = nil; goTo($0, line) }, onDelete: { menuFor = nil; cutting = $0 },
               onDrill: { menuFor = nil; onDrill(rep.id, $0, $1) })
        .presentationDetents([.medium, .large]).presentationBackground(Theme.background)
    }
    .sheet(item: Binding(get: { cutting.map(RepRef.init) }, set: { cutting = $0?.id })) { ref in
      cutSheet(rep, ref.id).presentationDetents([.height(260)]).presentationBackground(Theme.background)
    }
    .sheet(item: Binding(get: { saving.map { LineRef(sans: $0) } }, set: { saving = $0?.sans })) { ref in
      SaveSheet(sans: ref.sans, color: rep.color, source: savingSource, onSaved: { _, _, saved in
        if saved.count == ref.sans.count { descend(saved.last!, at: at) }
      }, onClose: { saving = nil })
      .presentationDetents([.medium, .large]).presentationBackground(Theme.background)
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

  /// A line that leaves the book goes through the Save sheet, which checks the move first.
  private func leavesBook(_ rep: Repertoire, _ index: ReferenceIndex, _ sans: [String]) -> Bool {
    let kinds = lineKinds(index, sans, rep.color)
    return bookLength(kinds) < kinds.count
  }

  private func onBoardMove(_ rep: Repertoire, _ index: ReferenceIndex, _ kids: [RepMove], _ pathSans: [String], _ move: LegalMove) {
    if let existing = kids.first(where: { $0.san == move.san }) {
      nodeId = existing.id
      if lineTip.map({ pathTo(rep, $0).contains { $0.id == existing.id } }) != true { lineTip = existing.id }
      return
    }
    if leavesBook(rep, index, pathSans + [move.san]) {
      savingSource = .manual
      saving = pathSans + [move.san]
      return
    }
    pending = move
  }

  private func addFromBook(_ rep: Repertoire, _ index: ReferenceIndex, _ pathSans: [String], _ san: String, _ at: String?) {
    if leavesBook(rep, index, pathSans + [san]) {
      savingSource = .book
      saving = pathSans + [san]
      return
    }
    store.update { $0.addLine(repId, pathSans + [san], .fixed(.book)) }
    descend(san, at: at)
    toasts.show("\(san) added")
  }

  private func commit(_ rep: Repertoire, _ pathSans: [String], _ move: LegalMove) {
    store.update { $0.addLine(repId, pathSans + [move.san], .fixed(.manual)) }
    pending = nil
    descend(move.san, at: nodeId)
    toasts.show("\(move.san) added")
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
