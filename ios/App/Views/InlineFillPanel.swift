import Book
import ChessCore
import Model
import Shared
import SwiftUI

/// Under the board while a run adds moves to the Playbook, laid out as Growth's
/// hole: the reply you had no answer to, the answers with who recommends them,
/// Undo and Done. Each pick is saved and played, the book's most played reply
/// comes back, and Done goes back to the game.
struct InlineFillPanel: View {
  @Bindable var model: RunModel

  var body: some View {
    let fill = model.fill
    VStack(spacing: 0) {
      HStack(alignment: .center, spacing: 4) {
        Button { model.undoAdded() } label: {
          Icon(name: "undo", size: 18).foregroundStyle(Theme.text2).frame(width: 38, height: 38).background(Circle().fill(Theme.surface))
        }
        .buttonStyle(.plain).disabled(fill?.steps.isEmpty ?? true).opacity(fill?.steps.isEmpty ?? true ? 0.35 : 1)
        .frame(maxWidth: .infinity, alignment: .leading)
        GrowthPrompt(side: model.run.color, who: theyPlayed, ctx: context).layoutPriority(1)
        Button("Done") { model.doneAdding() }
          .buttonStyle(PlayButtonStyle(height: 38, radius: 11, font: 14)).fixedSize()
          .frame(maxWidth: .infinity, alignment: .trailing)
      }
      if model.atHole && !model.thinking {
        PlaySection(title: "Answer it", aside: fill.map { answerAside(added: $0.added, of: $0.size) })
        ScrollView {
          HoleAnswerList(source: model) { model.addMove($0) }
        }
        .scrollIndicators(.hidden).scrollBounceBehavior(.basedOnSize)
        .tip(
          model.tip, when: model.tip == .firstMove || model.tip == .reply, arrow: .down, arrowAt: 0.12,
          onDismiss: model.dismissTip)
      }
    }
  }

  /// "They played Nf3", the reply you are answering.
  private var theyPlayed: String {
    model.myTurn ? model.run.played.last.map { "They played \($0)" } ?? "Your move" : "Thinking\u{2026}"
  }

  private var context: String? {
    guard model.myTurn, !model.thinking, let fen = walkSan(Array(model.run.played.dropLast())).fens.last,
      let last = model.run.played.last,
      let reply = popularReplies(model.index, fen, 0).first(where: { $0.san == last })
    else { return nil }
    return "\(JS.string(reply.share))% of strong players' games \u{00b7} \(formatGameCount(reply.games))"
  }
}
