import Book
import ChessCore
import Model
import SwiftUI

/// One opening that has extensions in it, as the review lists it.
struct ExtensionOpening {
  var rep: Repertoire
  var opening: DerivedOpening
  var kinds: [String: MoveKind]
  /// Its extensions, each by its first move.
  var roots: [String]
  /// Of those, the ones not reviewed yet.
  var open: Int
  /// Saved mistakes, wherever they sit in an extension.
  var mistakes: Int
}

/// Every opening with an extension in it, over both sides: `useExtensionOpenings`.
func extensionOpenings(_ reps: [Repertoire], _ index: ReferenceIndex) -> [ExtensionOpening] {
  var out: [ExtensionOpening] = []
  for rep in reps {
    let kinds = treeKinds(rep, index)
    let roots = extensionRoots(rep, kinds)
    if roots.isEmpty { continue }
    for opening in openingsIn(rep, index) {
      let inside = Set(subtreeIds(rep, opening.rootId))
      let above = Set(pathTo(rep, opening.rootId).map(\.id))
      // An extension that starts above the opening's root holds the whole opening, so it belongs to it too.
      let mine = roots.filter { inside.contains($0.id) || above.contains($0.id) }
      if mine.isEmpty { continue }
      let ids = Set(mine.flatMap { subtreeIds(rep, $0.id) })
      out.append(ExtensionOpening(
        rep: rep, opening: opening, kinds: kinds, roots: mine.map(\.id),
        open: mine.filter { !keptCurrent(rep, $0) }.count, mistakes: ids.filter { kinds[$0] == .mistake }.count))
    }
  }
  return out
}

/// The Extensions review: one opening at a time, drawn as a graph of your
/// lines with the extensions outlined. Keep or Remove act on the whole
/// extension the move belongs to; a mistake can be switched to the book's
/// move.
struct ExtensionsView: View {
  let onBack: () -> Void
  @Environment(AppStore.self) private var store
  @Environment(Toasts.self) private var toasts
  @State private var pickedId: String?
  @State private var choosing = false
  @State private var extOnly = false
  @State private var selected: String?

  var body: some View {
    let openings = store.index.map { extensionOpenings(store.state.repertoireList, $0) } ?? []
    let current = openings.first { $0.opening.id == pickedId } ?? openings.first
    VStack(spacing: 0) {
      AppBar(title: "Extensions", onBack: onBack)
      if let current, let index = store.index {
        review(current, openings, index)
      } else {
        EmptyNote(title: "No extensions", hint: "Every move in your Playbook is a book move.")
        Spacer()
      }
    }
    .sheet(isPresented: $choosing) {
      ScrollView {
        VStack(alignment: .leading, spacing: 14) {
          Text("Extensions").font(.system(size: 22, weight: .heavy)).foregroundStyle(Theme.text)
          ListCard {
            ForEach(openings, id: \.opening.id) { o in
              Button {
                pickedId = o.opening.id
                selected = nil
                choosing = false
              } label: {
                HStack(spacing: 12) {
                  SideSquare(color: o.rep.color)
                  Text(o.opening.name).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.text).lineLimit(1)
                  Spacer()
                  if o.mistakes > 0 { ExtPill(text: "\(o.mistakes)", mistake: true) }
                  ExtPill(text: "\(o.roots.count)")
                }
                .padding(.horizontal, 16).frame(minHeight: 54).contentShape(Rectangle())
              }
              .buttonStyle(.plain)
            }
          }
        }
        .padding(20)
      }
      .presentationDetents([.medium, .large]).presentationBackground(Theme.background)
    }
  }

  @ViewBuilder private func review(_ current: ExtensionOpening, _ openings: [ExtensionOpening], _ index: ReferenceIndex) -> some View {
    let rep = current.rep, opening = current.opening, kinds = current.kinds
    let rows = layoutGraph(rep, index, kinds, opening.rootId, extOnly: extOnly)
    let cells = rows.flatMap { $0.cells.filter { $0.nodeId != nil } }
    let firstExt = cells.first { $0.kind != .move(.book) }?.nodeId ?? cells.first?.nodeId
    let selId = selected.flatMap { s in rep.nodes[s] != nil && cells.contains { $0.nodeId == s } ? s : nil } ?? firstExt
    let sel = selId.flatMap { rep.nodes[$0] }
    let selPath = sel.map { pathTo(rep, $0.id) } ?? []
    let selKind = sel.flatMap { kinds[$0.id] } ?? .book
    let root = sel.flatMap { extensionRoot(rep, kinds, $0.id) }
    let rootPly = root.map { pathTo(rep, $0.id).count - 1 } ?? 0
    let size = root.map { subtreeIds(rep, $0.id).count } ?? 0
    let kept = root.map { keptCurrent(rep, $0) } ?? false
    let yours = sel.map { fenTurn($0.fenBefore) == rep.color } ?? false
    let bookMove = sel.flatMap { s in selKind == .mistake && yours ? bookMoves(index, s.fenBefore).first { $0 != s.san } : nil }

    ScrollView {
      VStack(alignment: .leading, spacing: 0) {
        Button { choosing = true } label: {
          HStack(spacing: 8) {
            SideSquare(color: rep.color, size: 11)
            Text(opening.name).font(.system(size: 20, weight: .heavy)).foregroundStyle(Theme.text).lineLimit(1)
            if openings.count > 1 { Icon(name: "down", size: 16).foregroundStyle(Theme.text) }
            Spacer(minLength: 0)
          }
          .padding(.horizontal, 2).padding(.top, 4).padding(.bottom, 12)
        }
        .buttonStyle(.plain).disabled(openings.count < 2)
        if let sel {
          HStack(spacing: 12) {
            MiniBoard(sans: selPath.map(\.san), orientation: rep.color, size: 100, lastMove: true)
            VStack(alignment: .leading, spacing: 6) {
              HStack(spacing: 5) {
                Text(moveLabel(selPath.count - 1, sel.san))
                if selKind == .mistake { Icon(name: "warn", size: 15).foregroundStyle(Theme.warn) }
              }
              .font(.system(size: 18, weight: .heavy, design: .monospaced))
              .foregroundStyle(selKind == .book ? Theme.accentInk : Theme.ext)
              .padding(.horizontal, 9).padding(.vertical, 4)
              .background(RoundedRectangle(cornerRadius: 9).fill(selKind == .book ? Theme.accent : .clear))
              .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(selKind == .book ? .clear : Theme.accent, lineWidth: 1.5))
              if root != nil { Text("\(size) \(size == 1 ? "move" : "moves")").font(.system(size: 14)).foregroundStyle(Theme.text2) }
            }
            Spacer(minLength: 0)
          }
          .padding(10).background(RoundedRectangle(cornerRadius: 18).fill(Theme.surface))
        }
        HStack(spacing: 8) {
          Text(sansToMoveText(opening.path)).font(.system(size: 13, design: .monospaced)).foregroundStyle(Theme.text2).lineLimit(1)
          Spacer(minLength: 0)
          SegmentedControl(value: $extOnly, options: [(false, "All"), (true, "Extensions")]).fixedSize()
        }
        .padding(.top, 14).padding(.bottom, 8)
        ScrollView(.horizontal, showsIndicators: false) {
          ExtensionGraphView(rows: rows, rootPly: opening.path.count, selected: selId) { selected = $0 }
        }
        if let root {
          VStack(spacing: 8) {
            if let bookMove, let sel {
              SheetButton("Switch to \(moveLabel(selPath.count - 1, bookMove))", style: .accent) {
                switchTo(rep, sel, bookMove, ply: selPath.count - 1)
              }
            }
            HStack(spacing: 8) {
              SheetButton(kept ? "Kept" : "Keep", style: .plain) { keep(rep, root, rootPly) }.disabled(kept)
              SheetButton("Remove", style: .danger) { remove(rep, root, rootPly) }
            }
          }
          .padding(.top, 14)
        }
      }
      .padding(.horizontal, 16).padding(.bottom, 28)
    }
  }

  private func remove(_ rep: Repertoire, _ root: RepMove, _ ply: Int) {
    let label = moveLabel(ply, root.san)
    var undo: PlaybookUndo?
    store.update { undo = $0.removeNode(rep.id, root.id) }
    guard let undo else { return }
    Haptics.buzz(12, on: store.state.settings.hapticFeedback)
    selected = nil
    toasts.show("Removed \(label)", action: ("Undo", { store.update { $0.undo(undo) } }))
  }

  private func keep(_ rep: Repertoire, _ root: RepMove, _ ply: Int) {
    store.update { $0.tidyKeep(rep.id, root.id) }
    Haptics.buzz(8, on: store.state.settings.hapticFeedback)
    toasts.show("Kept \(moveLabel(ply, root.san))")
  }

  private func switchTo(_ rep: Repertoire, _ sel: RepMove, _ san: String, ply: Int) {
    var undo: PlaybookUndo?
    store.update { undo = $0.tidySwitch(rep.id, sel.id, san) }
    guard let undo else { return }
    Haptics.buzz(12, on: store.state.settings.hapticFeedback)
    selected = nil
    toasts.show("Switched to \(moveLabel(ply, san))", action: ("Undo", { store.update { $0.undo(undo) } }))
  }
}
