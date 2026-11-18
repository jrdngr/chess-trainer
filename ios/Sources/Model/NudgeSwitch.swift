import Book
import ChessCore
import Shared

/// Rare book moves that are familiar anyway.

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
