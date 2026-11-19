import ChessCore
import Game
import Model
import SwiftUI

/// Tidy: the places where another move brings your lines together, most moves
/// removed first. Each card shows both lines from where they split.
struct TidyView: View {
  let onBack: () -> Void

  @Environment(AppStore.self) private var store
  @Environment(Toasts.self) private var toasts

  var body: some View {
    let finds = store.index.map { store.services.tidy.finds(store.state, $0) } ?? []
    VStack(spacing: 0) {
      AppBar(title: "Tidy", onBack: onBack)
      ScrollView {
        VStack(spacing: 12) {
          Text("Simplify your Playbook by switching to lines that transpose into each other.")
            .font(.system(size: 15)).foregroundStyle(Theme.text2).lineSpacing(3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 18).fill(Theme.surface))
          ForEach(finds, id: \.id) { find in
            TidyCard(find: find, onSwitch: { switchTo(find) })
          }
        }
        .padding(.horizontal, 16).padding(.bottom, 28)
      }
    }
    .task(id: TidyScan.Input(store.state)) {
      if let index = store.index { await store.services.tidy.run(TidyScan.Input(store.state), index) }
    }
  }

  private func switchTo(_ find: TidyFind) {
    var undo: PlaybookUndo?
    store.update {
      setEventPlace(.tidy)
      undo = $0.tidySwitch(find.playbookId, find.nodeId, find.suggestion)
      setEventPlace(.playbook)
    }
    guard let undo else { return }
    Haptics.buzz(12, on: store.state.settings.hapticFeedback)
    toasts.show("Switched to \(moveLabel(find.path + [find.suggestion]))", action: ("Undo", { store.update { $0.undo(undo) } }))
  }
}

/// One find: the current line on the left, the target line on the right, both
/// stepped together from where they split.
struct TidyCard: View {
  let find: TidyFind
  let onSwitch: () -> Void
  @State private var step = 0

  var body: some View {
    let frame = tidyFrame(find, step)
    VStack(spacing: 12) {
      HStack(alignment: .top, spacing: 10) {
        side("Current line", fen: frame.currentFen, move: frame.currentMove, tint: Theme.bad, known: false)
        side("Target line", fen: frame.targetFen, move: frame.targetMove, tint: step > find.joins ? Theme.text3 : Theme.good, known: frame.known)
      }
      stepper
      SheetButton("Switch these moves", style: .accent, action: onSwitch)
    }
    .padding(12)
    .background(RoundedRectangle(cornerRadius: 18).fill(Theme.surface))
    .onChange(of: find.id) { step = 0 }
  }

  private func side(_ label: String, fen: String, move: LegalMove?, tint: SwiftUI.Color, known: Bool) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(label).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.text2)
      BoardView(
        fen: fen, orientation: find.color, interactive: false, lastMove: nil,
        highlights: move.map { [$0.from: tint.opacity(0.6), $0.to: tint] } ?? [:], coordinates: false, onMove: { _ in })
        .aspectRatio(1, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(known ? Theme.good : .clear, lineWidth: 3))
    }
    .frame(maxWidth: .infinity)
  }

  private var stepper: some View {
    let steps = find.target.count
    return HStack(spacing: 10) {
      stepButton("prev", enabled: step > 0) { step -= 1 }
      HStack(spacing: 5) {
        ForEach(0..<steps, id: \.self) { i in
          Circle().fill(i < step ? Theme.text : Theme.surface3).frame(width: 6, height: 6)
        }
      }
      .frame(minWidth: 60)
      stepButton("next", enabled: step < steps) { step += 1 }
    }
  }

  private func stepButton(_ icon: String, enabled: Bool, _ action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Icon(name: icon, size: 18).foregroundStyle(Theme.text)
        .frame(width: 44, height: 34)
        .background(RoundedRectangle(cornerRadius: 10).fill(Theme.surface2))
    }
    .buttonStyle(.plain)
    .disabled(!enabled)
    .opacity(enabled ? 1 : 0.4)
  }
}

/// The Playbook tab's way into Tidy: a wand and the count, boxed like the pawn
/// counter. Shown only while Tidy has something to list.
struct TidyButton: View {
  let onOpen: () -> Void
  @Environment(AppStore.self) private var store

  var body: some View {
    let count = store.index.flatMap { store.services.tidy.count(store.state, $0) } ?? 0
    Group {
      if count > 0 {
        Button(action: onOpen) {
          HStack(spacing: 4) {
            Icon(name: "wand", size: 19).foregroundStyle(Theme.text)
            Text("\(count)").font(.system(size: 17, weight: .semibold).monospacedDigit()).foregroundStyle(Theme.text)
          }
          .padding(.horizontal, 8).frame(minWidth: 58, minHeight: 37)
          .background(RoundedRectangle(cornerRadius: 11).fill(Theme.surface2))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Tidy, \(count)")
      }
    }
    .task(id: TidyScan.Input(store.state)) {
      if let index = store.index { await store.services.tidy.run(TidyScan.Input(store.state), index) }
    }
  }
}
