import Book
import ChessCore
import Model
import Shared
import SwiftUI

/// What sits under the board as the sitting goes: the answers to pick from,
/// or the reveal.
struct GrowthPhaseView: View {
  @Bindable var model: GrowthModel
  let exits: GrowthView.Exits

  var body: some View {
    VStack(spacing: 0) {
      // Whose move sits under the app bar; under the board only what there is to do.
      switch model.phase {
      case .hole where !model.held && !model.waitingForEngine && !model.choices.isEmpty:
        hole
      case .lost: lost
      case .done: GrowthReveal(model: model, exits: exits)
      default: EmptyView()
      }
    }
  }

  /// Undo and Done over the answers, where a new player sees them from the first reply.
  private var hole: some View {
    VStack(spacing: 0) {
      HStack(alignment: .center, spacing: 4) {
        Button { model.undoLast() } label: {
          Icon(name: "undo", size: 18).foregroundStyle(Theme.text2).frame(width: 38, height: 38).background(Circle().fill(Theme.surface))
        }
        .buttonStyle(.plain).disabled(model.session.history.isEmpty).opacity(model.session.history.isEmpty ? 0.35 : 1)
        .frame(maxWidth: .infinity, alignment: .leading)
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
