import Book
import ChessCore
import Model
import Shared
import SwiftUI

/// Under the board while a run adds moves to the Playbook: Undo, the
/// "Adding new moves" pill and Done, then Growth's answers with who recommends
/// them. Each pick is saved and played, the book's most played reply comes
/// back, and Done goes back to the game.
struct InlineFillPanel: View {
  @Bindable var model: RunModel
  /// The answers past the first few are shown.
  @State private var showAll = false

  /// Answers listed before More: as many as fit under the board.
  static let shown = 3

  var body: some View {
    let fill = model.fill
    let ranked = model.atHole && !model.thinking ? model.ranked : []
    let hidden = showAll ? 0 : max(ranked.count - Self.shown, 0)
    VStack(spacing: 0) {
      HStack(alignment: .center, spacing: 4) {
        Button { model.undoAdded() } label: {
          Icon(name: "undo", size: 18).foregroundStyle(Theme.text2).frame(width: 38, height: 38).background(Circle().fill(Theme.surface))
        }
        .buttonStyle(.plain).disabled(fill?.steps.isEmpty ?? true).opacity(fill?.steps.isEmpty ?? true ? 0.35 : 1)
        .frame(maxWidth: .infinity, alignment: .leading)
        Text("Adding new moves").font(.system(size: 15, weight: .bold)).foregroundStyle(Theme.background).lineLimit(1)
          .padding(.horizontal, 16).padding(.vertical, 8).background(Capsule().fill(Theme.accent))
          .fixedSize().layoutPriority(1)
        Button("Done") { model.doneAdding() }
          .buttonStyle(PlayButtonStyle(height: 38, radius: 11, font: 14)).fixedSize()
          .frame(maxWidth: .infinity, alignment: .trailing)
      }
      if !ranked.isEmpty {
        HStack(spacing: 10) {
          Text("Answer it")
          if hidden > 0 {
            Button("\(hidden) more") { showAll = true }
              .font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.accent).buttonStyle(.plain)
          }
          Spacer()
          if let fill { Text(answerAside(added: fill.added, of: fill.size)).foregroundStyle(Theme.text3) }
        }
        .font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.text2)
        .padding(.horizontal, 4).padding(.top, 14).padding(.bottom, 8)
        ScrollView {
          HoleAnswerList(source: model, limit: showAll ? nil : Self.shown) { model.addMove($0) }
        }
        .scrollIndicators(.hidden).scrollBounceBehavior(.basedOnSize)
        .tip(
          model.tip, when: model.tip == .firstMove || model.tip == .reply, arrow: .down, arrowAt: 0.12,
          onDismiss: model.dismissTip)
      }
    }
    // Each hole starts with the first few answers.
    .onChange(of: model.run.fen) { showAll = false }
  }
}
