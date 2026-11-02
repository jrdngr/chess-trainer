import Book
import ChessCore
import Model

/// The answers a hole offers: the book's
/// (or the engine's past it), a familiar move pulled in from further down,
/// coloured toward your patterns, ranked, and given the arrows' roles.
extension GrowthModel {
  /// The moves offered here; nil past the book while the engine works them out.
  func choices(at fen: String) -> [Reply]? {
    _ = GrowthEngine.shared.version
    return choicesAt(index, fen, 4)
  }

  /// The moves offered at a hole, none while the engine is still working.
  var choices: [Reply] { phase == .hole ? choices(at: run.fen) ?? [] : [] }

  /// At a hole with nothing offered yet: the engine is finding moves.
  var waitingForEngine: Bool { phase == .hole && choices(at: run.fen) == nil }

  /// At a hole where the book has nothing at all: the engine's moves are on offer.
  var pastBook: Bool { phase == .hole && optionsAt(index, run.fen, 1).isEmpty }

  private var nudgePrefs: NudgePrefs { NudgePrefs(priority: prefs.nudgePriority, pawns: prefs.nudgePawns) }

  /// Familiar moves the book leaves out or ranks too low, each put to the engine first.
  var offBookAsked: [String] {
    guard phase == .hole else { return [] }
    return familiarOffBook(live, index, run.path, run.fen, nudgePrefs, minShare)
  }

  /// The ones the engine passed: only these may take the yellow arrow.
  var offBook: [String] {
    let checks = EngineChecks.shared
    return offBookAsked.filter { checks.isSound(run.fen, $0) == true }
  }

  /// Ask the engine about the familiar moves off the book.
  func askSoundness() {
    for san in offBookAsked { EngineChecks.shared.askSound(run.fen, san) }
  }

  /// The answers drawn and listed, coloured toward the moves that keep your Playbook narrow.
  var toned: [NudgedMove] {
    guard phase == .hole else { return [] }
    let off = offBook
    let key = "\(run.fen)|\(off.joined(separator: " "))|\(live?.nodes.count ?? 0)|\(nudgePrefs)|\(GrowthEngine.shared.version)"
    return tonedMemo.get(key) { nudged(off) }
  }

  private func nudged(_ off: [String]) -> [NudgedMove] {
    let options = choices
    let drawn = options.compactMap { option in applySan(run.fen, option.san).map { DrawnMove(san: option.san, from: $0.from, to: $0.to) } }
    let candidates = (pastBook ? options : popularReplies(index, run.fen, minShare)).map { NudgeCandidate(san: $0.san, share: $0.share) }
      + off.map { NudgeCandidate(san: $0, share: 0) }
    return nudgeArrows(live, index, run.path, run.fen, drawn, candidates, nudgePrefs, minShare, Set(off), true)
  }

  /// Every answer on offer, with a familiar move pulled in from further down the book.
  var listed: [Reply] {
    let options = choices
    guard let far = toned.first(where: { $0.tone == .towardFar }), !options.contains(where: { $0.san == far.san }) else { return options }
    let option = popularReplies(index, run.fen, 0).first { $0.san == far.san }
      ?? Reply(san: far.san, games: 0, white: 0, draw: 0, black: 0, share: 0)
    return options + [option]
  }

  /// The eval bar over the position, and at a hole what each answer does to it.
  var evals: GrowthEngine.Evals {
    GrowthEngine.shared.evals(run.fen, phase == .hole ? listed.map(\.san) : [])
  }

  func askEvals() {
    GrowthEngine.shared.askEvals(run.fen, phase == .hole ? listed.map(\.san) : [])
  }

  /// What an answer does to the eval, from your side; nil while the engine works.
  func delta(_ san: String, _ evals: GrowthEngine.Evals) -> Double? {
    guard let after = evals.moves[san], let position = evals.position else { return nil }
    return deltaFor(run.color, position, after)
  }

  /// The answers as strong players rank them, the engine settling ties.
  var ranked: [Reply] {
    let evals = evals
    return byShare(listed, san: \.san, share: { $0.share }, { delta($0, evals) })
  }

  /// Who recommends what: strong players' top reply, the engine's best two.
  var roles: [RoleArrow] {
    let evals = evals
    return roleArrows(run.fen, listed.map { ListedAnswer(san: $0.san, share: $0.share) }, { delta($0, evals) })
  }
}
