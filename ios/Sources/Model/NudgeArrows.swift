import Book
import ChessCore
import Shared

/// Choosing the nudges' colours, and saying why.

public enum NudgeTone: String, Sendable {
  case toward
  case towardFar = "toward-far"
  case away
}

public struct DrawnMove: Equatable, Sendable {
  public var san: String
  public var from: String
  public var to: String
  public init(san: String, from: String, to: String) {
    self.san = san
    self.from = from
    self.to = to
  }
}

public struct NudgedMove: Equatable, Sendable {
  public var san: String
  public var from: String
  public var to: String
  public var tone: NudgeTone?
  public var reason: String?
  /// The reason in a word or two, for a pill on the move's row.
  public var pill: String?
}

/// A move you may choose, with its share of games.
public struct NudgeCandidate: Equatable, Sendable {
  public var san: String
  public var share: Double
  public init(san: String, share: Double) {
    self.san = san
    self.share = share
  }
}

public enum TowardKind: String, Sendable {
  case transposes, heads, habit, pawns
}

enum AwayKind { case closes, passed }

/// Appended to the reason of a book move strong players rarely choose.
public let RARELY_PLAYED = " · rarely played"

/// Whether a move after `path` is the first one of its side in the game.
public func isFirstMove(_ path: [String]) -> Bool { path.count < 2 }

/// The arrows to draw at a position you are adding a move in, coloured.
///
/// `drawn` is what the board would show without nudges, `candidates` every
/// move you may choose there, most played first; `offBook` names those the
/// book lacks. The familiar move is always on the board: in its own arrow's
/// place when already drawn, else in place of the same piece's arrow, else of
/// the third — or, with `append`, alongside the rest.
public func nudgeArrows(
  _ rep: Repertoire?, _ index: ReferenceIndex, _ path: [String], _ fen: String, _ drawn: [DrawnMove],
  _ candidates: [NudgeCandidate], _ prefs: NudgePrefs, _ minShare: Double,
  _ offBook: Set<String> = [], _ append: Bool = false
) -> [NudgedMove] {
  var out = drawn.map { NudgedMove(san: $0.san, from: $0.from, to: $0.to) }
  // Your first move of the game picks the opening: it is left plain.
  guard let rep, !candidates.isEmpty, !isFirstMove(path) else { return out }
  let profile = profileOf(rep, index)
  if profile.nodes.isEmpty { return out }

  let (signals, fam) = signalsFor(profile, index, path, fen, candidates.map(\.san), prefs, minShare)
  var share: [String: Double] = [:]
  for c in candidates { share[c.san] = c.share }

  if let green = pickToward(signals, prefs.priority, share) {
    let reason = towardReason(green.signal, green.kind, index, fam) + (offBook.contains(green.signal.san) ? RARELY_PLAYED : "")
    let pill = towardPill(green.signal, green.kind)
    if let at = out.firstIndex(where: { $0.san == green.signal.san }) {
      out[at].tone = .toward
      out[at].reason = reason
      out[at].pill = pill
    } else if let move = applySan(fen, green.signal.san) {
      let nudged = NudgedMove(san: move.san, from: move.from, to: move.to, tone: .towardFar, reason: reason, pill: pill)
      let samePiece = out.firstIndex { $0.from == move.from }
      if append { out.append(nudged) }
      else if let samePiece { out[samePiece] = nudged }
      else if out.count < 3 { out.append(nudged) }
      else { out[out.count - 1] = nudged }
    }
  }

  let onBoard = signals.filter { signal in out.contains { $0.san == signal.san && $0.tone == nil } }
  if let red = pickAway(onBoard, prefs.priority, share), let at = out.firstIndex(where: { $0.san == red.signal.san }) {
    out[at].tone = .away
    out[at].reason = awayReason(red.signal, red.kind, fam)
    out[at].pill = red.kind == .closes ? "Closes off your habit" : "Breaks a habit"
  }
  return out
}

private func towardOrder(_ priority: NudgePriority) -> [TowardKind] {
  priority == .transposition ? [.transposes, .heads, .habit, .pawns] : [.habit, .pawns, .transposes, .heads]
}

private func towardStrength(_ s: Signals, _ kind: TowardKind, _ lenient: Bool = false) -> Double {
  switch kind {
  case .transposes: return s.transposes
  case .heads: return s.heads
  case .habit:
    let via = habitVia(s, lenient)
    return Double(via == .move ? s.habit : via == .setup ? s.setupUses : 0)
  case .pawns: return Double(s.pawns)
  }
}

/// How familiar a move is: the first kind it scores in, and how strongly. Nil when it is not.
func familiarity(_ s: Signals, _ priority: NudgePriority, _ lenient: Bool = false) -> (kind: TowardKind, rank: Int, strength: Double)? {
  for (rank, kind) in towardOrder(priority).enumerated() {
    let strength = towardStrength(s, kind, lenient)
    if strength > 0 { return (kind, rank, strength) }
  }
  return nil
}

private func pickToward(_ signals: [Signals], _ priority: NudgePriority, _ share: [String: Double]) -> (signal: Signals, kind: TowardKind)? {
  for kind in towardOrder(priority) {
    // Strongest first; the more popular move on a tie.
    let best = signals.filter { towardStrength($0, kind) > 0 }.jsSorted { a, b in
      let d = towardStrength(b, kind) - towardStrength(a, kind)
      return d != 0 ? d : (share[b.san] ?? 0) - (share[a.san] ?? 0)
    }.first
    if let best { return (best, kind) }
  }
  return nil
}

private func awayStrength(_ s: Signals, _ kind: AwayKind) -> Double {
  if kind == .closes { return Double(s.closes) }
  // A move of a setup you use is not one you turn down, whatever its own count.
  if habitVia(s) == .setup { return 0 }
  return s.passed >= HABIT_MIN && s.passed > s.habit ? Double(s.passed) : 0
}

enum HabitVia { case move, setup }

/// A habit is a move you choose when you can: at least `HABIT_MIN` times, and
/// at least as often as you pass it over; failing that, the setup it belongs
/// to, held to the same test. `lenient` drops the test against the times you
/// passed it up, for a move you have just played over the board.
func habitVia(_ s: Signals, _ lenient: Bool = false) -> HabitVia? {
  if s.habit >= HABIT_MIN && (lenient || s.habit >= s.passed) { return .move }
  if s.setup != nil && s.setupUses >= HABIT_MIN && (lenient || s.setupUses >= s.setupPassed) { return .setup }
  return nil
}

func pickAway(_ signals: [Signals], _ priority: NudgePriority, _ share: [String: Double]) -> (signal: Signals, kind: AwayKind)? {
  let order: [AwayKind] = priority == .transposition ? [.closes, .passed] : [.passed, .closes]
  for kind in order {
    // Strongest first; the less popular move on a tie.
    let worst = signals.filter { awayStrength($0, kind) > 0 }.jsSorted { a, b in
      let d = awayStrength(b, kind) - awayStrength(a, kind)
      return d != 0 ? d : (share[a.san] ?? 0) - (share[b.san] ?? 0)
    }.first
    if let worst { return (worst, kind) }
  }
  return nil
}

func towardReason(_ signal: Signals, _ kind: TowardKind, _ index: ReferenceIndex, _ fam: String?, _ lenient: Bool = false) -> String {
  switch kind {
  case .transposes:
    let into = lineName(index, signal.transposesInto ?? [])
    return "\(signal.san) \(signal.transposesNow ? "transposes" : "can transpose") into your \(into)"
  case .heads:
    return "\(signal.san) heads toward your \(lineName(index, signal.headsInto ?? []))"
  case .habit:
    if habitVia(signal, lenient) == .setup, let setup = signal.setup {
      return "You \(setup.doing) in \(signal.setupUses) \(linesOf(signal.setupFrom, fam))"
    }
    return "You play \(signal.san) in \(signal.habit) \(linesOf(signal.habitFrom, fam))"
  case .pawns:
    return "\(signal.san) reaches your usual \(fam.map { "\(shortFamily($0)) " } ?? "")pawns"
  }
}

private func towardPill(_ signal: Signals, _ kind: TowardKind) -> String {
  switch kind {
  case .transposes: return signal.transposesNow ? "Transposes" : "Can transpose"
  case .heads: return "Heads toward"
  case .habit: return habitVia(signal) == .setup ? "Your setup" : "Your habit"
  case .pawns: return "Your pawns"
  }
}

func awayReason(_ signal: Signals, _ kind: AwayKind, _ fam: String?) -> String {
  kind == .closes
    ? "\(signal.san) closes off \(countOf(signal.closes)) of your \(linesOf(signal.closesFrom, fam))"
    : "You've chosen another move over \(signal.san) \(signal.passed) times in your \(linesOf(signal.passedFrom, fam))"
}

/// "Catalan lines", or "English and Réti lines" when the count comes from kin.
private func linesOf(_ families: [String], _ fam: String?) -> String {
  let named = families.filter { !$0.isEmpty }.prefix(2).map(shortFamily)
  if named.isEmpty { return fam.map { "\(shortFamily($0)) lines" } ?? "lines" }
  return "\(named.joined(separator: " and ")) lines"
}

/// The name of one of your lines, as short as it can be and still say which.
private func lineName(_ index: ReferenceIndex, _ line: [String]) -> String {
  guard let deepest = namesAlong(index, line).last?.name, !deepest.isEmpty else { return "prep" }
  let variation = deepest.range(of: ": ").map { String(deepest[$0.upperBound...]) } ?? deepest
  return "\(variation) line"
}

private func countOf(_ n: Int) -> String { n == 1 ? "one" : String(n) }
