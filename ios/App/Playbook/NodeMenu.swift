import ChessCore
import Model
import SwiftUI

/// One move in the tree: its schedule, where it came from, how many branches
/// follow, its note, and what it is against the book. `TreeRow`.
struct TreeRow: View {
  let rep: Repertoire
  let node: RepMove
  let kind: MoveKind?
  let card: Card?
  let ourTurn: Bool
  let onOpen: () -> Void
  let onMenu: () -> Void

  static let kindLabel: [MoveKind: String] = [.book: "Book", .rare: "Rare", .mistake: "Mistake", .past: "Past the book"]

  var body: some View {
    let kids = childrenOf(rep, node.id).count
    let meta = [
      sourceLabel(node.source), kids == 0 ? "end of line" : "\(kids) \(kids == 1 ? "branch" : "branches")",
      card != nil && ourTurn ? describeDue(card!.due) : nil,
    ].compactMap { $0 }.joined(separator: " \u{00b7} ")
    HStack(spacing: 0) {
      Button(action: onOpen) {
        HStack(spacing: 12) {
          if ourTurn { Circle().fill(dotColor).frame(width: 8, height: 8) }
          Text(node.san).font(.system(size: 17, weight: .bold).monospacedDigit()).foregroundStyle(Theme.text).frame(minWidth: 56, alignment: .leading)
          VStack(alignment: .leading, spacing: 2) {
            Text(meta).font(.system(size: 12.5)).foregroundStyle(Theme.text3).lineLimit(1)
            if let note = node.note { Text(note).font(.system(size: 12.5)).foregroundStyle(Theme.text2).lineLimit(1) }
          }
          Spacer(minLength: 0)
          if let kind, kind != .book { ExtPill(text: Self.kindLabel[kind]!, mistake: kind == .mistake) }
          if node.preferred && ourTurn { Chip(text: "main", tone: .accent) }
        }
        .frame(minHeight: 34).contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      IconButton(icon: "more", size: 20, plain: true, action: onMenu)
    }
    .padding(.leading, 16).padding(.trailing, 8).padding(.vertical, 10)
  }

  private var dotColor: SwiftUI.Color {
    guard let card else { return Theme.surface3 }
    switch card.stage {
    case .new: return Theme.accent
    case .learning: return Theme.warn
    case .review: return card.interval >= 21 ? Theme.good : SwiftUI.Color(hex: 0x7dd3fc)
    }
  }
}

/// What can be done to one move: go there, make it main,
/// note it, reorder it, or delete it and everything after it. `NodeMenu`.
struct NodeMenu: View {
  let rep: Repertoire
  let nodeId: String
  let onNavigate: (String) -> Void
  let onDelete: (String) -> Void
  @Environment(AppStore.self) private var store
  @Environment(Toasts.self) private var toasts
  @State private var note = ""
  @State private var editing = false

  var body: some View {
    let rep = store.state.repertoires[self.rep.id] ?? self.rep
    if let node = rep.nodes[nodeId] {
      let ourMove = fenTurn(node.fenBefore) == rep.color
      let siblings = childrenOf(rep, node.parentId)
      ScrollView {
        VStack(alignment: .leading, spacing: 0) {
          SheetHead(title: node.san, moves: sansToMoveText(pathTo(rep, node.id).map(\.san)))
          if editing {
            TextField("Why this move?", text: $note, axis: .vertical)
              .font(.system(size: 15)).foregroundStyle(Theme.text).lineLimit(3...6)
              .padding(.horizontal, 16).padding(.vertical, 14).background(RoundedRectangle(cornerRadius: 14).fill(Theme.surface))
            HStack(spacing: 8) {
              SheetButton("Cancel", style: .plain) { editing = false }
              SheetButton("Save", style: .primary) {
                store.update { $0.annotate(rep.id, node.id, note) }
                editing = false
              }
            }
            .padding(.top, 10)
          } else {
            if let existing = node.note {
              Text(existing).font(.system(size: 13)).foregroundStyle(Theme.text2).padding(14).frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 18).fill(Theme.surface)).padding(.bottom, 10)
            }
            ListCard {
              row("Go here", trailing: "chevron") { onNavigate(node.id) }
              if ourMove && siblings.count > 1 && !node.preferred {
                row("Set as main", trailing: "star") {
                  store.update { $0.preferMove(rep.id, node.id) }
                  toasts.show("\(node.san) is now main")
                }
              }
              row(node.note == nil ? "Add note" : "Edit note", trailing: "note") {
                note = node.note ?? ""
                editing = true
              }
              if siblings.count > 1 {
                HStack {
                  Text("Reorder").font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.text)
                  Spacer()
                  IconButton(icon: "up", size: 16) { store.update { $0.reorder(rep.id, node.id, -1) } }
                  IconButton(icon: "down", size: 16) { store.update { $0.reorder(rep.id, node.id, 1) } }
                }
                .padding(.horizontal, 16).frame(minHeight: 54)
              }
            }
            SheetButton("Delete branch", icon: "trash", style: .danger) { onDelete(node.id) }.padding(.top, 12)
          }
        }
        .padding(20)
      }
    }
  }

  private func row(_ title: String, meta: String? = nil, trailing: String, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      HStack {
        VStack(alignment: .leading, spacing: 2) {
          Text(title).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.text)
          if let meta { Text(meta).font(.system(size: 12.5)).foregroundStyle(Theme.text3) }
        }
        Spacer()
        Icon(name: trailing, size: 18).foregroundStyle(Theme.text3)
      }
      .padding(.horizontal, 16).frame(minHeight: 54).contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }
}
