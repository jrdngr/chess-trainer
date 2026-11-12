import ChessCore
import Model
import SwiftUI

/// Tidy: places where another move is closer to the rest of your lines.
/// Switching keeps that move and drops yours, with everything under it.
/// `focus` is a find from the end of a round, shown first and open, once:
/// `onFocusShown` tells the owner it has been pinned.
struct TidyView: View {
  let scan: TidyScan
  var focus: TidyFind?
  var onFocusShown: () -> Void = {}
  let onBack: () -> Void

  @Environment(AppStore.self) private var store
  @Environment(Toasts.self) private var toasts
  @State private var pinned: TidyFind?
  @State private var open: String?

  var body: some View {
    let state = store.state
    let pinnedLive = pinned.flatMap { p in state.repertoires[p.repertoireId]?.nodes[p.nodeId] != nil ? p : nil }
    let rest = (scan.finds ?? []).filter { $0.id != pinnedLive?.id }
    let list = pinnedLive.map { [$0] + rest } ?? rest
    let shown = scan.shown(list)
    let reps = repertoiresIn(state.repertoireList, state.settings.selection.color)
    VStack(spacing: 0) {
      AppBar(title: "Tidy", onBack: onBack)
      ScrollView {
        VStack(alignment: .leading, spacing: 0) {
          SelectionBar()
          Text("Places where another move is closer to the rest of your lines. Switching keeps that move and drops yours, with everything under it.")
            .font(.system(size: 13.5)).foregroundStyle(Theme.text2).lineSpacing(3).padding(.horizontal, 2).padding(.top, 12).padding(.bottom, 14)
          if reps.isEmpty {
            EmptyNote(title: "No lines yet", hint: "Add some first. Tidy looks for lines that could converge.")
          } else if shown.isEmpty && scan.looking == nil {
            EmptyNote(title: "Nothing to tidy in \(whereText)", hint: "Your moves here are as close to your other lines as any.")
          }
          if let looking = scan.looking {
            Text("Looking through \(looking) positions").font(.system(size: 12)).foregroundStyle(Theme.text3)
              .frame(maxWidth: .infinity).padding(.top, 4).padding(.bottom, 12)
          }
          VStack(spacing: 10) {
            ForEach(shown, id: \.id) { find in
              TidyCard(
                find: find, pinned: find.id == pinnedLive?.id, open: open == find.id,
                checking: find.offBook && EngineChecks.shared.isSound(find.fen, find.suggestion) == nil,
                onToggle: { open = open == find.id ? nil : find.id }, onSwitch: { switchTo(find) })
            }
          }
        }
        .padding(.horizontal, 16).padding(.bottom, 28)
      }
    }
    .onAppear {
      if let focus {
        pinned = focus
        open = focus.id
        onFocusShown()
      }
    }
    .task(id: list.map(\.id)) { scan.ask(list) }
  }

  private var whereText: String {
    let selection = store.state.settings.selection
    guard let tree = store.tree else { return "your Playbook" }
    let region = regionsBySide(tree, selection).first?.node ?? tree.root
    return region.depth == 0 ? "your Playbook" : "the \(region.name)"
  }

  private func switchTo(_ find: TidyFind) {
    var undo: PlaybookUndo?
    store.update {
      setEventPlace(.tidy)
      undo = $0.tidySwitch(find.repertoireId, find.nodeId, find.suggestion)
      setEventPlace(.repertoire)
    }
    guard let undo else {
      toasts.show("That move cannot be played there")
      return
    }
    Haptics.buzz(12, on: store.state.settings.hapticFeedback)
    if pinned?.id == find.id { pinned = nil }
    toasts.show("Switched to \(moveLabel(find.path.count, find.suggestion))", action: ("Undo", { store.update { $0.undo(undo) } }))
  }
}

/// One find: the position, your move and the switch, and why. `TidyCard`.
struct TidyCard: View {
  let find: TidyFind
  let pinned: Bool
  let open: Bool
  let checking: Bool
  let onToggle: () -> Void
  let onSwitch: () -> Void
  @Environment(AppStore.self) private var store

  var body: some View {
    let color = nudgeColor(find.tone)
    VStack(alignment: .leading, spacing: 0) {
      if pinned {
        Text("FROM YOUR LAST ROUND").font(.system(size: 11.5, weight: .bold)).tracking(0.46).foregroundStyle(Theme.accent).padding(.bottom, 8)
      }
      Button(action: onToggle) {
        HStack(spacing: 12) {
          if !open { MiniBoard(sans: find.path, orientation: find.color, size: 76).clipShape(RoundedRectangle(cornerRadius: 6)) }
          VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 7) {
              ColorSquare(choice: find.color == .w ? .w : .b, size: 14)
              Text(moveLabel(find.path.count, find.mine)).foregroundStyle(Theme.text2)
              Text("\u{2192}").foregroundStyle(Theme.text3)
              Text(moveLabel(find.path.count, find.suggestion)).foregroundStyle(color)
            }
            .font(.system(size: 16, weight: .bold))
            Text(find.offBook ? find.reason + RARELY_PLAYED : find.reason).font(.system(size: 13)).foregroundStyle(color).lineSpacing(2)
              .multilineTextAlignment(.leading)
          }
          Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      if open {
        BoardView(fen: find.fen, orientation: find.color, interactive: false, lastMove: nil, arrows: arrows, onMove: { _ in })
          .padding(.top, 12)
        if let against {
          Text(against).font(.system(size: 13)).foregroundStyle(Theme.bad).padding(.top, 8)
        }
      }
      SheetButton(checking ? "Checking with the engine\u{2026}" : "Switch \u{00b7} removes \(find.removes) move\(find.removes == 1 ? "" : "s")", style: .accent, action: onSwitch)
        .disabled(checking).padding(.top, 8)
    }
    .padding(14)
    .background(RoundedRectangle(cornerRadius: 18).fill(Theme.surface))
    .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(pinned ? Theme.accent : .clear, lineWidth: 1.5))
  }

  /// Why your move works against your lines: worked out only for an open card.
  private var against: String? {
    guard open, let index = store.index, let rep = store.state.repertoires[find.repertoireId], let node = rep.nodes[find.nodeId] else { return nil }
    let line = pathTo(rep, node.parentId)
    let prefs = store.state.settings.growth
    return againstReason(
      rep, index, find.path, find.fen, find.mine, NudgePrefs(priority: prefs.nudgePriority, pawns: prefs.nudgePawns), prefs.minShare,
      SignalOptions(gone: goneWith(rep, index, find.nodeId), pathKeys: [positionKey(rep.rootFen)] + line.map { positionKey($0.fenAfter) }))
  }

  private var arrows: [BoardArrow] {
    var out: [BoardArrow] = []
    if let mine = applySan(find.fen, find.mine) { out.append(BoardArrow(from: mine.from, to: mine.to, color: against != nil ? Theme.bad : Theme.accent)) }
    if let theirs = applySan(find.fen, find.suggestion) { out.append(BoardArrow(from: theirs.from, to: theirs.to, color: nudgeColor(find.tone))) }
    return out
  }
}

/// The colour a nudge is drawn in: green toward, yellow toward from off the list, red away. `nudgeColor`.
func nudgeColor(_ tone: NudgeTone?) -> SwiftUI.Color {
  switch tone {
  case .toward: Theme.good
  case .towardFar: Theme.warn
  case .away: Theme.bad
  default: Theme.text
  }
}
