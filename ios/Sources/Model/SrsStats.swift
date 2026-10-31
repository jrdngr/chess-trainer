/// What Drill's setup shows of the schedule: `retention`, `masteryBuckets`
/// and `forecast` in `src/model/srs.ts`.

/// Retention across all reviewed cards, 0...1; nil when nothing is reviewed.
public func retention(_ cards: [Card]) -> Double? {
  let correct = cards.reduce(0) { $0 + $1.correct }
  let total = cards.reduce(0) { $0 + $1.correct + $1.incorrect }
  return total == 0 ? nil : Double(correct) / Double(total)
}

public struct MasteryBuckets: Equatable, Sendable {
  public var unseen = 0
  public var learning = 0
  public var young = 0
  public var mature = 0
}

/// Cards on a rough mastery ladder.
public func masteryBuckets(_ cards: [Card]) -> MasteryBuckets {
  var out = MasteryBuckets()
  for c in cards {
    if c.stage == .new { out.unseen += 1 }
    else if c.stage == .learning { out.learning += 1 }
    else if c.interval < 21 { out.young += 1 }
    else { out.mature += 1 }
  }
  return out
}

/// How many cards come due on each of the next `days` days.
public func forecast(_ cards: [Card], _ days: Int = 7, _ now: Double = Env.now()) -> [Int] {
  var out = Array(repeating: 0, count: days)
  for c in cards {
    if c.due <= now {
      out[0] += 1
      continue
    }
    let idx = Int(((c.due - now) / DAY).rounded(.down))
    if idx >= 0 && idx < days { out[idx] += 1 }
  }
  return out
}
