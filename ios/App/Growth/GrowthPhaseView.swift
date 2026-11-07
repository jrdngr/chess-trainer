import Book
import ChessCore
import Model
import Shared
import SwiftUI

/// What sits under the board as the sitting goes: whose move, the reply to
/// answer and the answers, or the reveal.
struct GrowthPhaseView: View {
  @Bindable var model: GrowthModel
  let exits: GrowthView.Exits

  var body: some View {
    let run = model.run
    VStack(spacing: 0) {
      switch model.phase {
      case .walking:
        let mine = isUsersTurn(run)
        GrowthPrompt(side: mine ? run.color : run.color.other, who: model.thinking ? "Thinking\u{2026}" : mine ? "Your move" : "Their move")
      case .answered:
        let past = pastTheBook(model.index, run.fen)
        let notes = [past ? "Past the book" : nil, model.added > 0 ? "\(model.added) of \(model.allowance) added" : nil].compactMap { $0 }
        GrowthPrompt(side: run.color.other, who: "Thinking\u{2026}", ctx: notes.isEmpty ? nil : notes.joined(separator: " \u{00b7} "))
      case .hole where !model.held:
        if model.waitingForEngine {
          GrowthPrompt(side: run.color, who: theyPlayed, ctx: "Past the book \u{00b7} the engine is finding moves\u{2026}")
        } else if !model.choices.isEmpty {
          hole
        }
      case .lost: lost
      case .done: GrowthReveal(model: model, exits: exits)
      default: EmptyView()
      }
    }
  }

  private var theyPlayed: String {
    model.run.hole.map { "They played \($0.san)" } ?? "Your prep ends here"
  }

  private var holeContext: String? {
    guard let hole = model.run.hole else { return nil }
    if hole.kept { return "In your Playbook, with no answer yet" }
    if hole.engine { return "Engine's pick \u{00b7} past the book" }
    return "\(JS.string(hole.share))% of strong players' games \u{00b7} \(formatGameCount(hole.games))"
  }

  /// Undo and Done flank the prompt, where a new player sees them from the first reply.
  private var hole: some View {
    VStack(spacing: 0) {
      HStack(alignment: .center, spacing: 4) {
        Button { model.undoLast() } label: {
          Icon(name: "undo", size: 18).foregroundStyle(Theme.text2).frame(width: 38, height: 38).background(Circle().fill(Theme.surface))
        }
        .buttonStyle(.plain).disabled(model.session.history.isEmpty).opacity(model.session.history.isEmpty ? 0.35 : 1)
        .frame(maxWidth: .infinity, alignment: .leading)
        GrowthPrompt(side: model.run.color, who: theyPlayed, ctx: holeContext).layoutPriority(1)
        Button("Done") { model.finish() }
          .buttonStyle(PlayButtonStyle(height: 38, radius: 11, font: 14)).fixedSize()
          .frame(maxWidth: .infinity, alignment: .trailing)
      }
      PlaySection(title: "Answer it", aside: answerAside(added: model.added, of: model.allowance))
      HoleAnswerList(source: model) { model.pick($0) }
    }
  }

  private var lost: some View {
    VStack(spacing: 8) {
      HStack {
        GrowthVerdict(tone: .no, text: "Not your prep")
        Spacer()
        Button(action: exits.close) {
          HStack(spacing: 6) { Text("Back"); Icon(name: "next", size: 16) }
        }
        .buttonStyle(PlayButtonStyle(kind: .primary, height: 38, radius: 11, font: 14))
      }
      HStack(spacing: 10) {
        compare("Playbook", preparedHere(model.start, model.run).map(\.san).joined(separator: " / "), Theme.good)
        compare("Played", model.session.wrong ?? "", Theme.bad)
      }
    }
  }

  private func compare(_ k: String, _ v: String, _ tone: SwiftUI.Color) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(k).font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.text3)
      Text(v.isEmpty ? "\u{2014}" : v).font(.system(size: 22, weight: .heavy)).foregroundStyle(tone)
    }
    .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 14).padding(.vertical, 12)
    .background(RoundedRectangle(cornerRadius: 16).fill(Theme.surface))
  }
}
