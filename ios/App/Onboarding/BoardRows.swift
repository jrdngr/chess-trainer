import Book
import ChessCore
import Model

/// What the board would put in, as the Playbook would list it: each opening a
/// saved line ends in, with your moves in it and the lines that reach it.
/// Read from the Playbook the lines would make, since none of them is in yet. `boardRows`.
func boardRows(_ state: AppState, _ tree: OpeningTree, _ index: ReferenceIndex, _ saved: [OnboardingLine]) -> [PendingOpening] {
  var next = state
  next.onboarded(tree, [], saved)
  var order: [String] = []
  var rows: [String: PendingOpening] = [:]
  for rep in next.repertoireList {
    let tips: [(tip: RepMove, line: OnboardingLine)] = saved.filter { $0.color == rep.color }.compactMap { line in
      let fen = walkSan(line.sans).fens.last
      let tip = rep.nodes.values.first { $0.fenAfter == fen && $0.san == line.sans.last }
      return tip.map { ($0, line) }
    }
    for opening in openingsIn(rep, index) {
      let inside = Set(subtreeIds(rep, opening.rootId))
      let mine = tips.filter { inside.contains($0.tip.id) }
      if mine.isEmpty { continue }
      // Your moves on the way to each line, the moves before the name included.
      let own = Set(mine.flatMap { pathTo(rep, $0.tip.id) }.filter { fenTurn($0.fenBefore) == rep.color }.map(\.id))
      // An opening called by Black's first move ("1...e5") goes in as that move, as a starter set's does.
      let sans = opening.name.first?.isNumber == true ? Array(opening.path.prefix(2)) : opening.path
      if rows[opening.id] == nil { order.append(opening.id) }
      rows[opening.id] = PendingOpening(
        key: opening.id, name: opening.name, color: rep.color, moves: own.count, sans: sans, lines: mine.map(\.line))
    }
  }
  return order.map { rows[$0]! }
}
