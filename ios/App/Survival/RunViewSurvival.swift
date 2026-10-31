import ChessCore
import Model
import SwiftUI

/// What a Survival run you set up shows that Autopilot's round does not.
extension RunView {
  /// The opening the run is announced as, by its trail.
  var introTrail: [String] {
    guard let catalog = store.catalog else { return [openingName(model.tree, model.introOpening)] }
    return selectionTrail(model.tree, catalog, model.introOpening)
  }

  /// Past the end of prep: the plan for the structure on the board, and Cash out when well ahead.
  @ViewBuilder var cards: some View {
    if model.session.prepStatus != .on {
      VStack(spacing: 0) {
        if cashOutOn, let trade = cashOut.trade(at: model.run.fen) {
          CashOutCard(trade: trade, model: cashOut, runId: model.run.id)
        }
        PlanCard(fen: model.shownFen, me: model.run.color).id(model.run.id)
      }
    }
  }

  /// Cash out is offered on your turn past prep, with nothing pending, when the engine has you well ahead.
  var cashOutOn: Bool {
    guard survival, model.live, !model.held, model.myTurn, model.session.prepStatus != .on, model.pending == nil,
      model.flash == nil, !model.momentHere, cashOut.dismissedIn != model.run.id,
      let base = model.baseline, base.fen == model.run.fen
    else { return false }
    return (model.run.color == .w ? base.cp : -base.cp) >= CASH_OUT_FROM
  }
}
