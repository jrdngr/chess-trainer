/// How often a reply you prepared comes up, at the least.
public let PREPARED_FLOOR = 0.15

/// The most of one position the lifted moves may take between them.
public let MAX_LIFTED = 0.5

/// Shares for the moves at one position, summing to 1. Floored moves the book
/// plays less than the level are lifted to it, the level being `floor` or less
/// so the lifted moves take at most `MAX_LIFTED` between them. The floor only
/// lifts: a floored move below `floor` that the level does not reach keeps its
/// book share, and the rest are scaled down to make room.
public func withFloor(_ weights: [Double], _ floored: [Bool], _ floor: Double = PREPARED_FLOOR) -> [Double] {
  let n = weights.count
  if n == 0 { return [] }
  let total = weights.reduce(0) { $0 + max(0, $1) }
  let base = total > 0 ? weights.map { max(0, $0) / total } : weights.map { _ in 1 / Double(n) }
  let wanted = base.indices.filter { floored[$0] && base[$0] < floor - 1e-12 }

  // The lifted moves are exactly the floored ones below the level they set.
  var level = floor
  var lifted = Set<Int>()
  for count in stride(from: wanted.count, through: 1, by: -1) {
    let at = min(floor, MAX_LIFTED / Double(count))
    let below = wanted.filter { base[$0] < at - 1e-12 }
    if below.count == count {
      level = at
      lifted = Set(below)
      break
    }
  }
  if lifted.isEmpty { return base }

  var kept = Set(wanted.filter { !lifted.contains($0) })
  var rest = 1 - level * Double(lifted.count) - base.indices.reduce(0) { kept.contains($1) ? $0 + base[$1] : $0 }
  var free = base.indices.reduce(0) { lifted.contains($1) || kept.contains($1) ? $0 : $0 + base[$1] }
  if free <= 0 || rest < 0 {
    // Nothing else can make room, so the kept moves give way too.
    kept = []
    rest = 1 - level * Double(lifted.count)
    free = base.indices.reduce(0) { lifted.contains($1) ? $0 : $0 + base[$1] }
  }
  let others = n - lifted.count - kept.count
  return base.indices.map { i in
    lifted.contains(i) ? level
      : kept.contains(i) ? base[i]
      : free > 0 ? base[i] / free * rest : others > 0 ? rest / Double(others) : 0
  }
}
