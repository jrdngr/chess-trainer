import Book
import ChessCore
import Model
import Shared
import SwiftUI

/// Under the board while a run adds moves to the Playbook: the reply you had
/// no answer to, the book's answers, Undo and Done. Each pick is saved and
/// played, the book's most played reply comes back, and Done goes back to the game.
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
        GrowthPrompt(side: model.run.color, who: "New move", ctx: fill.map { "\($0.added) of \($0.size)" }).layoutPriority(1)
        Button("Done") { model.doneAdding() }
          .buttonStyle(PlayButtonStyle(height: 38, radius: 11, font: 14)).fixedSize()
          .frame(maxWidth: .infinity, alignment: .trailing)
      }
      if model.myTurn && !model.thinking {
        Text(prompt).font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.text2)
          .frame(maxWidth: .infinity).padding(.top, 8)
        PlaySection(title: "Answer it", aside: context)
        ScrollView {
          ListCard {
            ForEach(model.fillChoices, id: \.san) { option in
              AnswerRow(option: option, role: nil, nudge: nil, delta: nil) { model.addMove(option.san) }
            }
          }
        }
        .scrollIndicators(.hidden).scrollBounceBehavior(.basedOnSize)
      }
    }
  }

  /// "Your Playbook has no answer to 3...Nf6."
  private var prompt: String {
    guard let last = model.run.played.last else { return "" }
    return "Your Playbook has no answer to \(moveLabel(last, ply: model.run.played.count - 1))."
  }

  private var context: String? {
    guard model.myTurn, !model.thinking, let fen = walkSan(Array(model.run.played.dropLast())).fens.last,
      let last = model.run.played.last,
      let reply = popularReplies(model.index, fen, 0).first(where: { $0.san == last })
    else { return nil }
    return "\(JS.string(reply.share))% of strong players' games"
  }
}
