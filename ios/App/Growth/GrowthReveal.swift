import ChessCore
import Model
import SwiftUI

/// The reveal once a batch is done: what was added, Undo, another batch,
/// and a game from here. Autopilot's batch shows only what was added.
struct GrowthReveal: View {
  @Bindable var model: GrowthModel
  let exits: GrowthView.Exits

  var body: some View {
    let full = exits.nextRound == nil
    let more = full ? model.more : nil
    VStack(spacing: 0) {
      GrowthVerdict(tone: model.verdict.tone, text: model.verdict.text)
      if full {
        if !model.session.history.isEmpty {
          HStack(spacing: 10) {
            wide("Undo", icon: "undo") { model.undoLast() }
            wide("Undo all") { model.undoAll() }
          }
          .padding(.top, 8)
        }
        if more == nil {
          Text("There are no moves left to answer here.").font(.system(size: 14)).foregroundStyle(Theme.text2)
            .frame(maxWidth: .infinity, alignment: .leading).padding(16)
            .background(RoundedRectangle(cornerRadius: 16).fill(Theme.surface)).padding(.top, 8)
        }
        if more != nil && !model.session.edge {
          wide("Add more moves", icon: "plus") { model.addMore() }.padding(.top, 12)
        }
        if let playFrom = exits.playFrom {
          wide("Play from here", icon: "play") { playFrom(model.run.fen) }.padding(.top, more != nil && !model.session.edge ? 8 : 12)
        }
        if let back = exits.back {
          Button(action: back) { Text("Back to openings").frame(maxWidth: .infinity) }
            .buttonStyle(PlayButtonStyle(kind: .bare)).padding(.top, 8)
        }
      }
    }
  }

  private func wide(_ title: String, icon: String? = nil, _ action: @escaping () -> Void) -> some View {
    Button(action: action) {
      HStack(spacing: 8) {
        if let icon { Icon(name: icon, size: 18) }
        Text(title)
      }
      .frame(maxWidth: .infinity)
    }
    .buttonStyle(PlayButtonStyle())
  }
}
