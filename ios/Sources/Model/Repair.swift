import ChessCore
import Shared

/// Repair: the prepared positions you got wrong, from the mistakes logged in
/// the app. No position is invented: each is one where you had a prepared
/// move and played something else.

public struct RepairItem: Sendable {
  /// Stable across rebuilds, so a fixed item can be skipped.
  public var id: String
  /// Where the mistake was made.
  public var source: MistakeSource
  public var playbookId: String
  /// The side you were playing: always this playbook's colour.
  public var color: Color
  public var key: String
  /// The position you are to move in.
  public var fen: String
  /// Moves from the start to that position.
  public var path: [String]
  public var lineText: String
  /// What you played there.
  public var played: String
  /// What the playbook says.
  public var expected: String
}

/// Every repairable position across the given playbooks, most recent mistake first.
public func buildRepairs(_ reps: [Playbook], _ mistakes: [Mistake]) -> [RepairItem] {
  let byId = Dictionary(reps.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
  var out: [RepairItem] = []
  for mistake in recentMistakes(mistakes, nil) {
    guard let rep = byId[mistake.playbookId], !mistake.expected.isEmpty else { continue }
    // Only ask about positions it is still this player's turn in.
    if fenTurn(mistake.fen) != rep.color { continue }
    let path = mistake.path ?? []
    out.append(RepairItem(
      id: "\(rep.id)#\(mistake.key)#mistake", source: mistake.source, playbookId: rep.id,
      color: rep.color, key: mistake.key, fen: mistake.fen, path: path,
      lineText: path.isEmpty ? "From a position you reached" : sansToMoveText(path),
      played: mistake.played, expected: mistake.expected))
  }
  return out
}
