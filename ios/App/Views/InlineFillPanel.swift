import Book
import ChessCore
import Model
import Shared
import SwiftUI

/// Under the board while a run adds moves to the Playbook: Undo and Done,
/// then Growth's answers with who recommends
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
        Button("Done") { model.doneAdding() }
          .buttonStyle(PlayButtonStyle(height: 38, radius: 11, font: 14)).fixedSize()
          .frame(maxWidth: .infinity, alignment: .trailing)
      }
      .zIndex(1)
      .tip(
        model.tip, when: model.tip == .extendLines || model.tip == .doneButton, arrowAt: model.tip == .doneButton ? 0.9 : 0.5,
        onDismiss: model.dismissTip)
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
        // Only three rows fit under the board: More scrolls the last three into view,
        // the top one flush with the list's edge so no row is cut in half.
        ScrollViewReader { scroller in
          ScrollView {
            HoleAnswerList(source: model, limit: showAll ? nil : Self.shown) { model.addMove($0) }
          }
          .scrollIndicators(.visible).scrollBounceBehavior(.basedOnSize)
          .onChange(of: showAll) {
            guard showAll, ranked.count > Self.shown else { return }
            let top = ranked[ranked.count - Self.shown].san
            withAnimation(.easeOut(duration: 0.3)) { scroller.scrollTo(top, anchor: .top) }
          }
        }
        .tip(
          model.tip, when: model.tip == .answerRow || model.tip == .pickAny, arrow: .down, arrowAt: 0.12,
          onDismiss: model.dismissTip)
      }
    }
    // Each hole starts with the first few answers.
    .onChange(of: model.run.fen) { showAll = false }
  }
}
