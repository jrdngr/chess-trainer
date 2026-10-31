import ChessCore
import Engine
import Model
import Observation
import SwiftUI

/// Cash out: when you are well ahead past your prep, a trade that keeps the
/// lead. `useCashOutCard` and `engine/cashOut.ts`: the hint engine's best few
/// moves, read for a capture taken straight back.
@MainActor @Observable
final class CashOut {
  /// The trade found for a position, once looked at.
  private(set) var found: (fen: String, trade: Trade?)?
  var open = false
  /// The run it was put away in, for the rest of that run: once said, it would only nag.
  var dismissedIn: String?
  private static var cache: [String: Trade?] = [:]

  /// The trade to offer here, once known.
  func trade(at fen: String) -> Trade? {
    guard let found, found.fen == fen else { return nil }
    return found.trade
  }

  func look(_ fen: String, _ me: ChessCore.Color) async {
    let key = "\(fen.split(separator: " ").prefix(2).joined(separator: " "))|\(me.rawValue)"
    if let known = Self.cache[key] {
      found = (fen, known)
      return
    }
    let snap = await HintEngine.shared.analyse(fen, EngineLimits(movetime: 600, multiPv: 4))
    guard !Task.isCancelled else { return }
    let trade = pickTrade(fen, snap.lines, me)
    if Self.cache.count > 200 { Self.cache.removeAll() }
    Self.cache[key] = trade
    found = (fen, trade)
  }

  /// The trade, drawn on the board while the card is open.
  func arrows(_ trade: Trade?) -> [BoardArrow] {
    guard open, let trade else { return [] }
    return [BoardArrow(from: trade.from, to: trade.to, color: Theme.good)]
  }
}

/// The Cash out row under the board: a tap shows the trade, the × puts it away for the run.
struct CashOutCard: View {
  let trade: Trade
  @Bindable var model: CashOut
  let runId: String

  var body: some View {
    HStack(spacing: 4) {
      Button { model.open.toggle() } label: {
        HStack(spacing: 8) {
          Text("CASH OUT").font(.system(size: 12, weight: .bold)).tracking(0.5).foregroundStyle(Theme.good)
          Text(model.open ? "Trade with \(trade.san)" : "Ahead: trade down?")
            .font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.text).lineLimit(1)
          Spacer(minLength: 0)
        }
        .padding(.vertical, 6).contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      Button {
        model.dismissedIn = runId
        model.open = false
      } label: {
        Icon(name: "close", size: 16).foregroundStyle(Theme.text2).frame(width: 32, height: 32)
      }
      .buttonStyle(.plain).accessibilityLabel("Hide cash out")
    }
    .padding(.leading, 12).padding([.trailing, .vertical], 4)
    .background(RoundedRectangle(cornerRadius: 16).fill(Theme.surface))
    .padding(.top, 8)
  }
}
