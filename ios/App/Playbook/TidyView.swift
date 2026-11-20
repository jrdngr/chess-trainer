import ChessCore
import Game
import Model
import SwiftUI

/// Tidy: the places where another move brings your lines together, most moves
/// removed first. Each card shows both lines from where they split, in the
/// color of why the move is offered.
struct TidyView: View {
  let onBack: () -> Void

  @Environment(AppStore.self) private var store
  @Environment(Toasts.self) private var toasts

  var body: some View {
    let finds = store.index.map { store.services.tidy.finds(store.state, $0) } ?? []
    let tip = tidyListTip(finds, seen: store.state.settings.seen)
    VStack(spacing: 0) {
      AppBar(title: "Tidy", onBack: onBack)
      ScrollView {
        VStack(spacing: 12) {
          ForEach(finds, id: \.id) { find in
            TidyCard(
              find: find, tip: tip?.findId == find.id ? tip?.tip : nil,
              onTip: { dismissTip(store, tip?.tip) }, onSwitch: { switchTo(find) }
            )
            .zIndex(tip?.findId == find.id ? 1 : 0)
          }
        }
        .padding(.top, 4)
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
  /// The tip explaining this card's kind, the first time it shows.
  let tip: GameTip?
  let onTip: () -> Void
  let onSwitch: () -> Void
  @State private var step = 0

  var body: some View {
    let frame = tidyFrame(find, step)
    let past = find.joins.map { step > $0 } ?? false
    VStack(spacing: 12) {
      HStack(alignment: .top, spacing: 10) {
        side(Text("Current line").foregroundStyle(Theme.text2), fen: frame.currentFen, move: frame.currentMove, tint: Theme.bad, known: false)
        side(
          Text(Self.label(find.kind)).foregroundStyle(Self.color(find.kind))
            .tip(text: tip?.text, arrowAt: 0.75, minWidth: 280, trailing: true, onDismiss: onTip),
          fen: frame.targetFen, move: frame.targetMove, tint: past ? Theme.text3 : Theme.good, known: frame.known)
      }
      stepper
      SheetButton("Switch these moves", style: .tint(Self.color(find.kind)), action: onSwitch)
    }
    .padding(12)
    .background(RoundedRectangle(cornerRadius: 18).fill(Theme.surface))
    .onChange(of: find.id) { step = 0 }
  }

  /// The right side's label: why this move is offered.
  static func label(_ kind: TowardKind) -> String {
    switch kind {
    case .transposes: "Joins your line"
    case .heads: "Can join your line"
    case .habit, .pawns: "Your usual move"
    }
  }

  /// Each kind's color, on its label and its Switch button.
  static func color(_ kind: TowardKind) -> SwiftUI.Color {
    switch kind {
    case .transposes: SwiftUI.Color(hex: 0x2dd4bf)
    case .heads: SwiftUI.Color(hex: 0x60a5fa)
    case .habit, .pawns: SwiftUI.Color(hex: 0xfbbf24)
    }
  }

  private func side(_ label: some View, fen: String, move: LegalMove?, tint: SwiftUI.Color, known: Bool) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      label.font(.system(size: 13, weight: .semibold)).lineLimit(1)
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
        .tip(
          text: store.state.settings.seen(.tidy) ? nil : GameTip.tidy.text, arrowAt: 0.89, minWidth: 264, trailing: true,
          onDismiss: { dismissTip(store, .tidy) })
      }
    }
    .task(id: TidyScan.Input(store.state)) {
      if let index = store.index { await store.services.tidy.run(TidyScan.Input(store.state), index) }
    }
  }
}
