import ChessCore
import Model
import SwiftUI

/// Under the board while a position is asked: the prompt, the last answer's
/// grade, and Moves, Explore and Stop.
struct DrillAskPanel: View {
  @Bindable var model: DrillSessionModel
  var close: () -> Void

  var body: some View {
    if let item = model.item {
      VStack(spacing: 0) {
        DrillPrompt(side: model.side, title: model.side == .w ? "White to move" : "Black to move", context: context(item))
          .opacity(model.held ? 0 : 1)
        if let last = model.drill.last {
          Spacer().frame(height: 8)
          Text("Last move\(last.item.expected.isEmpty ? "" : " \u{00b7} \(last.played)")")
            .font(.system(size: 12)).foregroundStyle(Theme.text3).padding(.top, 6)
          GradeRow(selected: last.grade, onPick: model.regrade).padding(.top, 8)
        }
        Spacer().frame(height: 16)
        HStack(spacing: 8) {
          SoftButton(title: model.showMoves ? "Hide moves" : "Moves") { model.showMoves.toggle() }
          SoftButton(title: "Explore") { model.explore = true }
          SoftButton(title: "Stop", action: close)
        }
        if model.showMoves {
          MoveTextCard(text: sansToMoveText(item.pathSans).isEmpty ? "Start" : sansToMoveText(item.pathSans)).padding(.top, 8)
        }
      }
    }
  }

  private func context(_ item: TrainingItem) -> String {
    var text = "Move \(item.pathSans.count / 2 + 1)"
    if item.expected.count > 1 { text += " \u{00b7} \(item.expected.count) options" }
    if model.extra { text += " \u{00b7} extra practice" }
    return text
  }
}

/// After a wrong answer: what the Playbook has, what was played, and the ways to look closer.
struct DrillWrongPanel: View {
  @Bindable var model: DrillSessionModel

  var body: some View {
    if let item = model.item {
      let preferred = model.preferred
      let alternatives = item.expected.filter { !$0.preferred }.map(\.san)
      VStack(spacing: 0) {
        HStack {
          DrillVerdict(tone: .no, text: "Wrong")
          Spacer()
          ContinueButton(action: model.continueAfterMiss)
        }
        CompareCards(good: ("Playbook", preferred?.san ?? ""), bad: ("Played", model.drill.played?.san ?? "")).padding(.top, 8)
        Spacer().frame(height: 16)
        HStack(spacing: 8) {
          if model.prefs.explain { SoftButton(title: "Why?") { model.why = true } }
          SoftButton(title: model.revealLine ? "Hide line" : "Show line") { model.revealLine.toggle() }
          SoftButton(title: "Explore") { model.explore = true }
        }
        if model.revealLine { MoveTextCard(text: sansToMoveText(item.continuation, item.fen)).padding(.top, 16) }
        if !alternatives.isEmpty || preferred?.note != nil {
          VStack(alignment: .leading, spacing: 8) {
            if let note = preferred?.note { Text(note).foregroundStyle(Theme.text2) }
            if !alternatives.isEmpty { Text("Also \(alternatives.joined(separator: ", "))").foregroundStyle(Theme.text3) }
          }
          .font(.system(size: 13)).frame(maxWidth: .infinity, alignment: .leading).padding(16)
          .background(RoundedRectangle(cornerRadius: 18).fill(Theme.surface)).padding(.top, 8)
        }
      }
    }
  }
}
