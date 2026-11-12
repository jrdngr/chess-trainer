import Book
import Game
import Model
import SwiftUI

/// Opens Tidy on a find, from wherever a round ends.
extension EnvironmentValues {
  @Entry var openTidy: ((TidyFind) -> Void)? = nil
}

/// The line under a miss when a move off your prep was closer to the rest of
/// your lines than the prepared one, in the colour Growth would draw it, and
/// the way to Tidy.
struct OffPrepHint: View {
  let find: TidyFind
  let onTidy: () -> Void
  var compact = false

  var body: some View {
    let ply = find.path.count
    VStack(alignment: .leading, spacing: 8) {
      Text("\(moveLabel(ply, find.suggestion)) is closer to the rest of your prep than \(moveLabel(ply, find.mine)). \(find.reason)\(find.offBook ? RARELY_PLAYED : "").")
        .font(.system(size: 13.5)).foregroundStyle(nudgeColor(find.tone)).lineSpacing(3)
        .frame(maxWidth: .infinity, alignment: .leading)
      Button(action: onTidy) {
        HStack(spacing: 6) {
          Icon(name: "merge", size: 16)
          Text("Tidy this").font(.system(size: 13.5, weight: .semibold))
        }
        .foregroundStyle(Theme.text).padding(.horizontal, 12).padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 10).fill(Theme.surface2))
      }
      .buttonStyle(.plain)
    }
    .padding(compact ? EdgeInsets(top: 0, leading: 14, bottom: 12, trailing: 14) : EdgeInsets(top: 14, leading: 14, bottom: 14, trailing: 14))
    .background { if !compact { RoundedRectangle(cornerRadius: 18).fill(Theme.surface) } }
    .padding(.top, compact ? 0 : 10)
  }
}

/// The misses whose move was closer to the rest of your lines than your prep, by ply.
func tidyHints(_ misses: [Miss], _ rep: Playbook?, _ index: ReferenceIndex, _ growth: GrowthPrefs) -> [Int: TidyFind] {
  var out: [Int: TidyFind] = [:]
  let opts = TidyOptions(prefs: NudgePrefs(priority: growth.nudgePriority, pawns: growth.nudgePawns), minShare: growth.minShare)
  for miss in misses {
    if let find = offPrepHint(rep, index, miss.fen, miss.played, miss.expected, opts) { out[miss.ply] = find }
  }
  return out
}
