import Foundation
import Model
import Shared

/// The windows the charts read over: `WINDOWS` in `StatsScreen.tsx`.
let STATS_WINDOWS: [(value: Int, label: String)] = [(30, "30 days"), (90, "90 days"), (365, "Year")]

/// Each mode's name in the tallies: `MODE_NAMES` in `recommend.ts`.
func modeName(_ mode: ActivityMode) -> String {
  switch mode {
  case .run: "Autopilot (old)"
  case .survival: "Survival"
  case .drill: "Drill"
  case .growth: "Growth"
  case .repair: "Repair"
  }
}

/// Rounds in every mode.
func roundsOf(_ stats: NodeStats) -> Int {
  ACTIVITY_MODES.reduce(0) { $0 + (stats.byMode[$1]?.rounds ?? 0) }
}

/// A rating as it is shown: `ratingText`.
func ratingText(_ rating: Double) -> String { "\(Int(JSRound(rating)))" }

/// A share as a whole percentage.
func percentText(_ share: Double) -> String { "\(Int(JSRound(share * 100)))%" }

/// "1st", "2nd", "11th".
func ordinal(_ n: Int) -> String {
  let suffix = (11...13).contains(n % 100) ? "th" : ["th", "st", "nd", "rd"].indices.contains(n % 10) ? ["th", "st", "nd", "rd"][n % 10] : "th"
  return "\(n)\(suffix)"
}

/// "1. e4 e5 2. Nf3": a line from the start, as `sansToMoveText` writes it.
func bookMoveText(_ sans: [String]) -> String {
  sans.enumerated().flatMap { i, san in i % 2 == 0 ? ["\(i / 2 + 1).", san] : [san] }.joined(separator: " ")
}

/// "Oct 1": a day, short.
func shortDate(_ at: Double) -> String {
  Date(timeIntervalSince1970: at / 1000).formatted(.dateTime.month(.abbreviated).day())
}
