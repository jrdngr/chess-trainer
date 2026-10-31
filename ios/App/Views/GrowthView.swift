import ChessCore
import Model
import SwiftUI

/// One batch of Growth: the reply you have no answer to, the book's answers
/// to choose from, and Next round once the batch is done.
struct GrowthView: View {
  @Bindable var model: GrowthModel
  let onNext: () -> Void

  var body: some View {
    VStack(spacing: 12) {
      VStack(spacing: 2) {
        Text("Grow \(model.offer.launch.opening.name)").font(.headline).foregroundStyle(Theme.text).lineLimit(1)
        Text("\(model.added) of \(model.allowance) added").font(.caption.monospacedDigit()).foregroundStyle(Theme.text2)
      }
      .padding(.top, 10)
      BoardView(
        fen: model.fen, orientation: model.session.run.color, interactive: false,
        lastMove: lastMoveOf(model.session.run.path), arrows: arrows, onMove: { _ in })
      .overlay(alignment: .top) {
        if let toast = model.toast {
          Text(toast).font(.subheadline.bold()).foregroundStyle(Theme.good)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(Capsule().fill(Theme.background.opacity(0.9))).padding(.top, 10)
        }
      }
      if let hole = model.session.run.hole, !model.done {
        Text("They play \(hole.san). Your answer?").font(.subheadline).foregroundStyle(Theme.text2)
      }
      if model.done {
        Text(model.session.edge ? "End of the book: this line is as far as Growth goes." : "Batch done.")
          .font(.subheadline).foregroundStyle(Theme.text2)
      } else {
        VStack(spacing: 8) {
          ForEach(model.choices, id: \.san) { reply in
            Button { model.pick(reply.san) } label: {
              HStack {
                Text(reply.san).font(.headline)
                Spacer()
                Text("\(JS(reply.share))% of strong players' games").font(.caption).foregroundStyle(Theme.book)
              }
              .padding(.horizontal, 14).padding(.vertical, 10)
              .background(RoundedRectangle(cornerRadius: 12).fill(Theme.surface))
            }
            .foregroundStyle(Theme.text)
          }
        }
        .padding(.horizontal)
      }
      Spacer()
      HStack {
        if !model.session.history.isEmpty && !model.done {
          Button("Undo") { model.undoLast() }.foregroundStyle(Theme.text2)
        }
        Spacer()
        if model.done {
          Button(action: onNext) { Label("Next round", systemImage: "chevron.right") }
            .buttonStyle(.borderedProminent).tint(Theme.accent)
        } else {
          Button("Done") { model.finish() }.foregroundStyle(Theme.text2)
        }
      }
      .padding()
    }
  }

  private var arrows: [BoardArrow] {
    guard !model.done, model.session.phase == .hole else { return [] }
    return onePerPiece(model.session.run.fen, model.choices.map(\.san), 3).map { BoardArrow(from: $0.from, to: $0.to, color: Theme.book) }
  }

  private func JS(_ share: Double) -> String {
    share == share.rounded() ? String(Int(share)) : String(share)
  }
}
