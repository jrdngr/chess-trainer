import ChessCore
import Model
import SwiftUI

/// The end of a run: how it ended, the board where it did, your prep's
/// summary and the rating it moved, and Next round. `End.tsx`.
struct EndView: View {
  let model: RunModel
  let finish: Finish
  let onNext: () -> Void
  let onGrow: (GrowOffer) -> Void
  let onExit: () -> Void
  @State private var atPrepEnd = false

  var body: some View {
    let state = finish.ended
    let prepPly = model.session.prepEnd?.count ?? state.misses.first?.ply
    let line = atPrepEnd && prepPly != nil ? Array(state.run.played.prefix(prepPly!)) : state.run.played
    ScrollView {
      VStack(spacing: 14) {
        Text(openingName(model.tree, model.openingId)).font(.title3.bold()).foregroundStyle(Theme.text)
        Text(endingTitle(finish.how, state.run.played.count)).font(.headline)
          .foregroundStyle(isBad ? Theme.bad : Theme.text2)
        BoardView(fen: walkSan(line).fens.last!, orientation: state.run.color, interactive: false, lastMove: lastMoveOf(line), onMove: { _ in })
          .padding(.horizontal)
        if prepPly != nil {
          Picker("", selection: $atPrepEnd) {
            Text("Final position").tag(false)
            Text("End of prep").tag(true)
          }
          .pickerStyle(.segmented).padding(.horizontal)
        }
        HStack(spacing: 28) {
          stat("\(state.moves)", "moves")
          stat("\(state.extras.points)", "points")
          stat("\(state.misses.count)", state.misses.count == 1 ? "miss" : "misses")
        }
        if let summary = prepSummary(model.session.answers.filter(\.correct).count, model.session.answers.count, model.session.prepTimes, model.session.bookMoves) {
          Text(summary).font(.subheadline).foregroundStyle(Theme.text2)
        }
        ratingCard
        if let offer = model.offer, offer.kind == "opening" {
          VStack(spacing: 8) {
            if let text = offer.text { Text(text).font(.subheadline).foregroundStyle(Theme.text) }
            Button("Grow this opening") { onGrow(offer) }.buttonStyle(.bordered).tint(Theme.good)
          }
          .padding().frame(maxWidth: .infinity).background(RoundedRectangle(cornerRadius: 14).fill(Theme.surface)).padding(.horizontal)
        }
        Button(action: onNext) {
          Label("Next round", systemImage: "chevron.right").frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent).tint(Theme.accent).controlSize(.large).padding(.horizontal)
        if let offer = model.offer, offer.kind == "line" {
          Button("Grow this line") { onGrow(offer) }.foregroundStyle(Theme.good)
        }
        Button("Done", action: onExit).foregroundStyle(Theme.text2)
      }
      .padding(.vertical)
    }
  }

  private var isBad: Bool {
    if case .blunder = finish.how { return true }
    if case .lost = finish.how { return true }
    return false
  }

  @ViewBuilder private var ratingCard: some View {
    if let r = model.ratings.byKey[model.openingId] {
      let before = rankOf(r.before), after = rankOf(r.after)
      VStack(spacing: 6) {
        Text("Rating").font(.caption).foregroundStyle(Theme.text2)
        HStack {
          Text(after.heldLabel).font(.headline).foregroundStyle(Theme.text)
          Spacer()
          Text("\(Int(JSRound(r.before))) \u{2192} \(Int(JSRound(r.after)))").font(.headline.monospacedDigit())
            .foregroundStyle(r.after >= r.before ? Theme.good : Theme.bad)
        }
        ProgressView(value: after.progress).tint(Theme.accent)
        if after.reached != before.reached {
          Text(after.reached > before.reached ? "Up to \(after.heldLabel)" : "Down to \(after.heldLabel)")
            .font(.subheadline.bold()).foregroundStyle(after.reached > before.reached ? Theme.good : Theme.bad)
        }
      }
      .padding().background(RoundedRectangle(cornerRadius: 14).fill(Theme.surface)).padding(.horizontal)
    }
  }

  private func stat(_ value: String, _ label: String) -> some View {
    VStack {
      Text(value).font(.title2.bold().monospacedDigit()).foregroundStyle(Theme.text)
      Text(label).font(.caption).foregroundStyle(Theme.text2)
    }
  }
}
