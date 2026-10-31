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
  /// The rating change has played over the board and gone down to its place.
  @State private var played = false

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
          .overlay {
            if let moment, !played {
              ZStack {
                Theme.background.opacity(0.6)
                RatingPlayback(moment: moment) { withAnimation { played = true } }
              }
              .transition(.opacity)
            }
          }
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

  /// The opening's own rating, as this run moved it.
  private var moment: RatingMoment? {
    guard let r = model.ratings.byKey[model.openingId], nodeById(model.tree, model.openingId).depth > 0 else { return nil }
    return RatingMoment(name: openingName(model.tree, model.openingId), before: r.before, after: r.after)
  }

  @ViewBuilder private var ratingCard: some View {
    if let moment, played {
      RatingCardView(moment: moment, rating: moment.after, shown: moment.after, width: rankOf(moment.after).progress)
        .padding(.horizontal)
        .transition(.move(edge: .top).combined(with: .opacity))
    }
  }

  private func stat(_ value: String, _ label: String) -> some View {
    VStack {
      Text(value).font(.title2.bold().monospacedDigit()).foregroundStyle(Theme.text)
      Text(label).font(.caption).foregroundStyle(Theme.text2)
    }
  }
}
