import Book
import ChessCore

/// A Growth sitting's moves, kept off the saved Playbook until Save Line.

public struct GrowthDraft {
  /// The side's tree with the sitting's moves in it.
  public private(set) var rep: Repertoire
  /// What Save Line writes, in order: the opening's own line first, then each answer's line.
  public private(set) var lines: [(sans: [String], source: SourceFor)] = []

  /// A draft on a saved tree, with a line kept from the start: the chosen opening's own moves.
  public init(_ saved: Repertoire, keep: [String]? = nil, source: MoveSource = .picker) {
    rep = saved
    if let keep, !keep.isEmpty { add(keep, .fixed(source)) }
  }

  public mutating func add(_ sans: [String], _ source: SourceFor) {
    rep = addLine(rep, sans, source).rep
    lines.append((sans, source))
  }

  /// Take a move and everything after it out, with every line that ran through it.
  public mutating func remove(_ nodeId: String) {
    guard rep.nodes[nodeId] != nil else { return }
    let cut = pathTo(rep, nodeId).map(\.san)
    rep = removeSubtree(rep, nodeId)
    lines.removeAll { $0.sans.count >= cut.count && Array($0.sans.prefix(cut.count)) == cut }
  }
}

extension AppState {
  /// Save Line: a draft's lines into the side's tree.
  public mutating func saveGrowth(_ repertoireId: String, _ draft: GrowthDraft) {
    for line in draft.lines { addLine(repertoireId, line.sans, line.source, via: .growth) }
  }
}
