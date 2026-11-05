import Book
import ChessCore
import Model
import SwiftUI

/// A sheet's title and the movetext under it.
struct SheetHead: View {
  var title: String
  var moves: String? = nil

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text(title).font(.system(size: 22, weight: .heavy)).foregroundStyle(Theme.text)
      if let moves, !moves.isEmpty { Text(moves).font(.system(size: 13, design: .monospaced)).foregroundStyle(Theme.text2).lineSpacing(5) }
    }
    .frame(maxWidth: .infinity, alignment: .leading).padding(.bottom, 12)
  }
}

/// A note under a sheet's buttons.
struct SheetNote: View {
  var text: String
  var centred = false
  var body: some View {
    Text(text).font(.system(size: 12.5)).foregroundStyle(Theme.text3).multilineTextAlignment(centred ? .center : .leading)
      .frame(maxWidth: .infinity, alignment: centred ? .center : .leading).padding(.top, 8).padding(.horizontal, 4)
  }
}

/// Start an opening by hand: pick a side and play the moves in. `NewOpeningSheet`.
struct NewOpeningSheet: View {
  let onReady: (String, ChessCore.Color) -> Void
  @Environment(AppStore.self) private var store
  @Environment(\.dismiss) private var dismiss
  @State private var color = ChessCore.Color.w

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      SheetHead(title: "Add an opening")
      SegmentedControl(value: $color, options: [(.w, "As White"), (.b, "As Black")])
      SheetNote(text: "Play the moves in and the book names the opening for you. It joins whatever you already have for that side.")
      Spacer().frame(height: 24)
      SheetButton("Start playing moves", style: .primary) {
        var repId = ""
        store.update { repId = $0.ensureRepertoire(color) }
        dismiss()
        onReady(repId, color)
      }
      Spacer()
    }
    .padding(20)
  }
}

/// What can be done to a whole side's tree. `SideMenu`.
struct SideMenu: View {
  let repId: String
  var onDeleted: () -> Void = {}
  let onClose: () -> Void
  @Environment(AppStore.self) private var store
  @Environment(Toasts.self) private var toasts
  @State private var confirming = false

  var body: some View {
    if let rep = store.state.repertoires[repId] {
      let moves = rep.nodes.count
      let trained = store.state.cards.values.filter { $0.repertoireId == rep.id }.count
      let side = rep.color == .w ? "White" : "Black"
      VStack(alignment: .leading, spacing: 0) {
        SheetHead(title: repertoireName(rep.color))
        ListCard {
          kv("Moves", "\(moves)")
          kv("Scheduled positions", "\(trained)")
        }
        Spacer().frame(height: 24)
        SheetButton(confirming ? "Tap again to delete" : "Delete everything as \(side)", icon: "trash", style: .danger) {
          if !confirming {
            confirming = true
            return
          }
          store.update { $0.removeRepertoire(rep.id) }
          onClose()
          onDeleted()
          toasts.show("Everything you play as \(side) deleted")
        }
        SheetNote(text: trained > 0
          ? "Every opening you play as \(side) goes, along with the schedule for \(trained) positions. This cannot be undone."
          : "Every opening you play as \(side) goes \u{2014} all \(moves) moves. This cannot be undone.", centred: true)
        Spacer()
      }
      .padding(20)
    }
  }

  private func kv(_ k: String, _ v: String) -> some View {
    HStack {
      Text(k).font(.system(size: 13)).foregroundStyle(Theme.text2)
      Spacer()
      Text(v).font(.system(size: 15, weight: .semibold).monospacedDigit()).foregroundStyle(Theme.text)
    }
    .padding(.horizontal, 16).frame(minHeight: 44)
  }
}
