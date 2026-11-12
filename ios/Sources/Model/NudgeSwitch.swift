import Book
import ChessCore
import Shared

/// Rare book moves, and comparing moves for Tidy.

/// Book moves ranked under `minShare` that are familiar anyway: they transpose, head toward your lines, or are a habit.
/// Soundness is not judged here; the engine does that before any is shown.
///
/// `habitsOnly` looks only at habits, which can be listed without trying every
/// legal move: what a scan of a whole playbook can afford.
public func familiarOffBook(
  _ rep: Playbook?, _ index: ReferenceIndex, _ path: [String], _ fen: String, _ prefs: NudgePrefs,
  _ minShare: Double, _ opts: SignalOptions = SignalOptions(), habitsOnly: Bool = false
) -> [String] {
  guard let rep, !isFirstMove(path) else { return [] }
  let profile = profileOf(rep, index)
  if profile.nodes.isEmpty { return [] }
  let listed = Set(bookMovesAt(index, fen, minShare))
  var sans: [String]
  if habitsOnly {
    let keys = opts.pathKeys ?? pathKeys(path, profile.rootFen)
    let context = contextOf(profile, index, familyAlong(index, keys), minShare)
    var counts = OrderedMap<String, Int>()
    var passed: [String: Int] = [:]
    for ply in (path.count - HABIT_PLIES)...(path.count + HABIT_PLIES) {
      for (move, n) in context.byPly[ply]?.entries ?? [] { counts[move] = (counts[move] ?? 0) + n }
      for (move, n) in context.passedByPly[ply]?.entries ?? [] { passed[move, default: 0] += n }
    }
    let listedMoves = Set(listed.map(sameMove))
    var moves = counts.entries.filter { $0.value >= HABIT_MIN && $0.value >= passed[$0.key] ?? 0 }.map(\.key)
    // Setups in use near here offer all their moves; the signals decide.
    let removed = Set(keys)
    let mine = yourMovesAlong(path, profile.color)
    for setup in setupsFor(profile.color) {
      if sum(near(context.setupUses[setup.id], path.count, removed, SETUP_PLIES)) < HABIT_MIN { continue }
      for move in setup.moves where signsSetup(setup, mine, move) && !moves.contains(move) { moves.append(move) }
    }
    let bySame = sansBySame(fen)
    sans = moves.filter { !listedMoves.contains($0) }.compactMap { bySame[$0] }
  } else {
    sans = legalMoves(fen).map(\.san).filter { !listed.contains($0) }
  }
  // The Playbook holds only book moves.
  sans = sans.filter { inBook(index, fen, $0) }
  if sans.isEmpty { return [] }
  var quiet = opts
  quiet.away = false
  let (signals, _) = signalsFor(profile, index, path, fen, sans, prefs, minShare, quiet)
  return signals.filter { s in
    guard let familiar = familiarity(s, prefs.priority) else { return false }
    return !habitsOnly || familiar.kind == .habit
  }.map(\.san)
}

/// The moves a habit names, as written in this position: "Ne5" may be "Nxe5"
/// here, which `sameMove` folded away.
private func sansBySame(_ fen: String) -> [String: String] {
  var out: [String: String] = [:]
  for san in legalSans(fen) { out[sameMove(san)] = san }
  return out
}

public struct Switch: Equatable, Sendable {
  public var san: String
  /// What makes it familiar.
  public var kind: TowardKind
  /// Why it is familiar.
  public var reason: String
  /// Why your move works against your lines, when it does.
  public var against: String?
}

/// The move among `others` closest to the rest of your lines, if it is closer
/// than `mine`; nil when `mine` is as familiar as any of them.
///
/// `opts.gone` should hold the positions only `mine`'s subtree reaches.
/// Familiarity is compared kind first, then strength; ties go to the earlier
/// of `others`. `played` marks a switch to a move just played over the board.
public func bestSwitch(
  _ rep: Playbook, _ index: ReferenceIndex, _ path: [String], _ fen: String, _ mine: String, _ others: [String],
  _ prefs: NudgePrefs, _ minShare: Double, _ opts: SignalOptions = SignalOptions(), against: Bool = true, played: Bool = false
) -> Switch? {
  let profile = profileOf(rep, index)
  if profile.nodes.isEmpty { return nil }
  var quiet = opts
  quiet.away = false
  let (signals, fam) = signalsFor(profile, index, path, fen, [mine] + others, prefs, minShare, quiet)
  let ours = signals.first { $0.san == mine }
  let bar = ours.flatMap { familiarity($0, prefs.priority, played) }
  func above(_ a: (rank: Int, strength: Double), _ b: (rank: Int, strength: Double)?) -> Bool {
    guard let b else { return true }
    return a.rank < b.rank || (a.rank == b.rank && a.strength > b.strength)
  }
  var best: (signal: Signals, kind: TowardKind, rank: Int, strength: Double)?
  for signal in signals where signal.san != mine {
    guard let f = familiarity(signal, prefs.priority, played) else { continue }
    if !above((f.rank, f.strength), bar.map { ($0.rank, $0.strength) }) { continue }
    // A habit is only a reason to switch where your move is a one-off; nor is a capture.
    if f.kind == .habit && ((ours?.habit ?? 0) > 0 || (ours?.setupUses ?? 0) > 0 || mine.contains("x")) { continue }
    if let b = best, !above((f.rank, f.strength), (b.rank, b.strength)) { continue }
    best = (signal, f.kind, f.rank, f.strength)
  }
  guard let best else { return nil }
  // Red for your move is worked out only now, for the one position shown.
  return Switch(
    san: best.signal.san, kind: best.kind,
    reason: towardReason(best.signal, best.kind, index, fam, played) + (best.kind == .habit ? ", \(mine) in none" : ""),
    against: against ? againstReason(rep, index, path, fen, mine, prefs, minShare, opts) : nil)
}

/// Why a move of yours works against your other lines — it closes them off,
/// or you keep choosing otherwise — or nil.
public func againstReason(
  _ rep: Playbook, _ index: ReferenceIndex, _ path: [String], _ fen: String, _ mine: String,
  _ prefs: NudgePrefs, _ minShare: Double, _ opts: SignalOptions = SignalOptions()
) -> String? {
  var loud = opts
  loud.away = true
  let (signals, fam) = signalsFor(profileOf(rep, index), index, path, fen, [mine], prefs, minShare, loud)
  guard let first = signals.first, let away = pickAway([first], prefs.priority, [:]) else { return nil }
  return awayReason(away.signal, away.kind, fam)
}

/// The positions only a subtree reaches: what goes if the move at its top is
/// switched away. A position another line also reaches stays.
public func goneWith(_ rep: Playbook, _ index: ReferenceIndex, _ nodeId: String) -> Set<String> {
  let profile = profileOf(rep, index)
  let inside = Set(subtreeIds(rep, nodeId))
  let outside = Set(profile.nodes.filter { !inside.contains($0.id) }.map(\.after))
  return Set(profile.nodes.filter { inside.contains($0.id) && !outside.contains($0.after) }.map(\.after))
}
