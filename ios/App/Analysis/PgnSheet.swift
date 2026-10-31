import SwiftUI
import UIKit

/// Paste a game in, or take the board's line out: the PGN sheet.
struct PgnSheet: View {
  @Binding var text: String
  /// The line on the board, for "From board".
  let visible: [String]
  let haptics: Bool
  let onLoad: ([String]) -> Void
  let onToast: (String) -> Void
  let onClose: () -> Void

  private var empty: Bool { text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

  var body: some View {
    SheetFrame(title: "PGN", detents: [.medium], onClose: onClose) {
      ZStack(alignment: .topLeading) {
        TextEditor(text: $text).scrollContentBackground(.hidden)
          .font(.system(size: 15)).foregroundStyle(Theme.text)
          .padding(.horizontal, 10).padding(.vertical, 6)
        if text.isEmpty {
          Text("Paste PGN").font(.system(size: 15)).foregroundStyle(Theme.text3)
            .padding(.horizontal, 15).padding(.vertical, 14).allowsHitTesting(false)
        }
      }
      .frame(minHeight: 180)
      .background(RoundedRectangle(cornerRadius: 12).fill(Theme.surface2))
      Spacer().frame(height: 8)
      HStack(spacing: 8) {
        WideButton(title: "From board", disabled: visible.isEmpty) { text = Pgn.export(visible) }
        WideButton(title: "Copy", disabled: empty) { copy() }
        WideButton(title: "Load", kind: .primary, disabled: empty) { load() }
      }
    }
  }

  private func copy() {
    UIPasteboard.general.string = text.trimmingCharacters(in: .whitespacesAndNewlines)
    Haptics.buzz(10, on: haptics)
    onToast("PGN copied")
  }

  private func load() {
    guard let moves = Pgn.mainline(text) else {
      onToast("Couldn't read that PGN")
      return
    }
    guard !moves.isEmpty else {
      onToast("No moves found")
      return
    }
    onLoad(moves)
  }
}
