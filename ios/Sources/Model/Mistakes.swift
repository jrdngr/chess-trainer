import Shared

/// Mistakes made inside the app.

public enum MistakeSource: String, Sendable, Codable {
  case drill, openingRun, play
}

public struct Mistake: Equatable, Sendable, Codable {
  public var id: String
  /// When it happened.
  public var at: Double
  public var source: MistakeSource
  public var playbookId: String
  /// positionKey of the position it was made in.
  public var key: String
  public var fen: String
  /// SAN path to the position, when the mode knows it.
  public var path: [String]?
  public var played: String
  public var expected: String

  public init(id: String = "", at: Double = 0, source: MistakeSource, playbookId: String, key: String, fen: String, path: [String]? = nil, played: String, expected: String) {
    self.id = id
    self.at = at
    self.source = source
    self.playbookId = playbookId
    self.key = key
    self.fen = fen
    self.path = path
    self.played = played
    self.expected = expected
  }
}

/// How many to keep.
public let MISTAKE_LIMIT = 200

/// Add one, newest last, replacing any earlier miss at the same position.
/// The mistake's `id` and `at` are set here.
public func addMistake(_ log: [Mistake], _ mistake: Mistake) -> [Mistake] {
  var entry = mistake
  entry.at = Env.now()
  entry.id = "\(mistake.playbookId)#\(mistake.key)"
  let rest = log.filter { $0.id != entry.id }
  return Array((rest + [entry]).suffix(MISTAKE_LIMIT))
}

/// A playbook's mistakes, newest first.
public func recentMistakes(_ log: [Mistake], _ playbookId: String? = nil) -> [Mistake] {
  log.filter { playbookId == nil || playbookId!.isEmpty || $0.playbookId == playbookId }
    .jsSorted { cmp($1.at, $0.at) }
}
