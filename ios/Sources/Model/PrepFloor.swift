/// How often a reply you prepared comes up, at the least. `src/model/prepFloor.ts`.
public let PREPARED_FLOOR = 0.15

/// The most of one position the lifted moves may take between them.
public let MAX_LIFTED = 0.5

/// Shares for the moves at one position, summing to 1, every floored move
/// lifted to at least `floor` and the rest scaled down to make room.
public func withFloor(_ weights: [Double], _ floored: [Bool], _ floor: Double = PREPARED_FLOOR) -> [Double] {
  let n = weights.count
  if n == 0 { return [] }
  let total = weights.reduce(0) { $0 + max(0, $1) }
  let base = total > 0 ? weights.map { max(0, $0) / total } : weights.map { _ in 1 / Double(n) }
  var shares = base
  var lifted = Set<Int>()
  for _ in 0...n {
    let each = min(floor, MAX_LIFTED / Double(max(1, lifted.count)))
    var changed = false
    for i in 0..<n where floored[i] && !lifted.contains(i) && shares[i] < each - 1e-12 {
      lifted.insert(i)
      changed = true
    }
    if !changed { break }
    let level = min(floor, MAX_LIFTED / Double(lifted.count))
    let rest = 1 - level * Double(lifted.count)
    let free = base.indices.reduce(0) { lifted.contains($1) ? $0 : $0 + base[$1] }
    let others = n - lifted.count
    shares = base.indices.map { i in
      lifted.contains(i) ? level : free > 0 ? base[i] / free * rest : others > 0 ? rest / Double(others) : 0
    }
  }
  return shares
}
