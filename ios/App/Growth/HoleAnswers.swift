import Book
import ChessCore
import Model

/// A screen that offers answers at a hole: Growth's sitting, and a Play run
/// adding moves. Both show the same answers, arrows and evals from these.
@MainActor protocol HoleAnswers: AnyObject {
  var index: ReferenceIndex { get }
  /// Answers are on offer now.
  var atHole: Bool { get }
  /// The position the answers are played from, and the moves to it.
  var holeFen: String { get }
  var holePath: [String] { get }
  /// The side adding moves.
  var answerColor: ChessCore.Color { get }
  /// The side's Playbook tree as it is now.
  var answerTree: Repertoire? { get }
  var nudgePrefs: NudgePrefs { get }
  var minShare: Double { get }
  var tonedMemo: Memo<[NudgedMove]> { get }
}

/// The answers a hole offers: the book's
/// (or the engine's past it), a familiar move pulled in from further down,
/// coloured toward your patterns, ranked, and given the arrows' roles.
extension HoleAnswers {
  /// The moves offered here; nil past the book while the engine works them out.
  func choices(at fen: String) -> [Reply]? {
    _ = GrowthEngine.shared.version
    return choicesAt(index, fen, 4)
  }

  /// The moves offered at a hole, none while the engine is still working.
  var choices: [Reply] { atHole ? choices(at: holeFen) ?? [] : [] }

  /// At a hole with nothing offered yet: the engine is finding moves.
  var waitingForEngine: Bool { atHole && choices(at: holeFen) == nil }

  /// At a hole where the book has nothing at all: the engine's moves are on offer.
  var pastBook: Bool { atHole && optionsAt(index, holeFen, 1).isEmpty }

  /// Familiar moves the book leaves out or ranks too low, each put to the engine first.
  var offBookAsked: [String] {
    guard atHole else { return [] }
    return familiarOffBook(answerTree, index, holePath, holeFen, nudgePrefs, minShare)
  }

  /// The ones the engine passed: only these may take the yellow arrow.
  var offBook: [String] {
    let checks = EngineChecks.shared
    return offBookAsked.filter { checks.isSound(holeFen, $0) == true }
  }

  /// Ask the engine about the familiar moves off the book.
  func askSoundness() {
    for san in offBookAsked { EngineChecks.shared.askSound(holeFen, san) }
  }

  /// The answers drawn and listed, coloured toward the moves that keep your Playbook narrow.
  var toned: [NudgedMove] {
    guard atHole else { return [] }
    let off = offBook
    let key = "\(holeFen)|\(off.joined(separator: " "))|\(answerTree?.nodes.count ?? 0)|\(nudgePrefs)|\(GrowthEngine.shared.version)"
    return tonedMemo.get(key) { nudged(off) }
  }

  private func nudged(_ off: [String]) -> [NudgedMove] {
    let options = choices
    let drawn = options.compactMap { option in applySan(holeFen, option.san).map { DrawnMove(san: option.san, from: $0.from, to: $0.to) } }
    let candidates = (pastBook ? options : popularReplies(index, holeFen, minShare)).map { NudgeCandidate(san: $0.san, share: $0.share) }
      + off.map { NudgeCandidate(san: $0, share: 0) }
    return nudgeArrows(answerTree, index, holePath, holeFen, drawn, candidates, nudgePrefs, minShare, Set(off), true)
  }

  /// Every answer on offer, with a familiar move pulled in from further down the book.
  var listed: [Reply] {
    let options = choices
    guard let far = toned.first(where: { $0.tone == .towardFar }), !options.contains(where: { $0.san == far.san }) else { return options }
    let option = popularReplies(index, holeFen, 0).first { $0.san == far.san }
      ?? Reply(san: far.san, games: 0, white: 0, draw: 0, black: 0, share: 0)
    return options + [option]
  }

  /// The eval bar over the position, and at a hole what each answer does to it.
  var evals: GrowthEngine.Evals {
    GrowthEngine.shared.evals(holeFen, atHole ? listed.map(\.san) : [])
  }

  func askEvals() {
    GrowthEngine.shared.askEvals(holeFen, atHole ? listed.map(\.san) : [])
  }

  /// What an answer does to the eval, from your side; nil while the engine works.
  func delta(_ san: String, _ evals: GrowthEngine.Evals) -> Double? {
    guard let after = evals.moves[san], let position = evals.position else { return nil }
    return deltaFor(answerColor, position, after)
  }

  /// The answers as strong players rank them, the engine settling ties.
  var ranked: [Reply] {
    let evals = evals
    return byShare(listed, san: \.san, share: { $0.share }, { delta($0, evals) })
  }

  /// Who recommends what: strong players' top reply, the engine's best two.
  var roles: [RoleArrow] {
    let evals = evals
    return roleArrows(holeFen, listed.map { ListedAnswer(san: $0.san, share: $0.share) }, { delta($0, evals) })
  }
}
