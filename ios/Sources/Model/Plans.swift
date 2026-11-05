import ChessCore

/// The plan for the board: a named structure's plan, in the variant its kings and
/// pieces call for, or a plan built from the position's features when no
/// structure fits.

/// A plan as the card shows it, its words and squares placed for the board.
public struct Plan: Equatable, Sendable {
  /// Names the plan across moves: the structure, its side `a`, and the variant.
  public var key: String
  public var label: String
  public var headline: String?
  public var steps: [PlanStep]
  public var runs: [[StepRun]]
  /// How many conditions picked it; the most specific plan wins.
  public var specificity: Int
  /// Side `a` of the structure, for the steps' needs.
  public var a: Color
}

/// One way to play a structure, for the kings and pieces it needs.
struct PlanVariant: Sendable {
  var id: String?
  var name: String?
  var when: [Need] = []
  var headline: (a: String, b: String)?
  /// Side `a`'s steps; nil keeps the structure's own.
  var a: [PlanStep]?
  var b: [PlanStep]?
}

/// The structures whose plan turns on where the kings went or what is left.
let PLAN_VARIANTS: [String: [PlanVariant]] = [
  "dragon": [
    PlanVariant(id: "yugoslav", name: "Yugoslav", when: [.notCastledShort(.a)]),
    PlanVariant(
      id: "classical", name: "Classical", when: [.castledShort(.a)], headline: ("Knight to d5", "The c-file"),
      a: [
        PlanStep(text: "Knight to d5 trades a key defender", goals: [Goal(piece: .n, to: "d5")]),
        PlanStep(text: "Push {f4–f5} for kingside space", goals: [Goal(piece: .p, to: "f5")], needs: [.pawnFile(.a, "f")]),
        PlanStep(text: "Watch for <Rxc3>, the exchange sacrifice"),
      ],
      b: [
        PlanStep(text: "Rook to c8 and the c-file", check: .file("c")),
        PlanStep(text: "Knight to c4 or e5", goals: [Goal(piece: .n, to: "c4"), Goal(piece: .n, to: "e5")]),
        PlanStep(text: "Push {b5} for queenside space", goals: [Goal(piece: .p, to: "b5")]),
      ]),
  ],
  "scheveningen": [
    PlanVariant(id: "keres", name: "Keres", when: [.notCastledShort(.a)]),
    PlanVariant(
      id: "classical", name: "Classical", when: [.castledShort(.a)], headline: ("Push f4", "Central break"),
      a: [
        PlanStep(text: "Push {f4}, then {e5} or {f5}", goals: [Goal(piece: .p, to: "f4")], needs: [.pawnFile(.a, "f")]),
        PlanStep(text: "Keep pressure on d6"),
        PlanStep(text: "Queen and rooks to the kingside"),
      ]),
  ],
  "kid-chain": [
    PlanVariant(id: "storm", name: "Storm", when: [.castledShort(.a)]),
    PlanVariant(
      id: "queenside", name: "Queenside", when: [.notCastledShort(.a)], headline: ("Queenside break", "Queenside play"),
      b: [
        PlanStep(text: "Break with {c6} to open the c-file", goals: [Goal(piece: .p, to: "c6")]),
        PlanStep(text: "Knight to c5 hits e4", goals: [Goal(piece: .n, to: "c5")]),
        PlanStep(text: "Keep {f5} ready"),
      ]),
  ],
  "carlsbad": [
    PlanVariant(id: "minority", name: "Minority attack", when: [.notCastledLong(.a)]),
    PlanVariant(
      id: "kingside", name: "Kingside attack", when: [.castledLong(.a)], headline: ("Kingside storm", "Kingside play"),
      a: [
        PlanStep(text: "Storm the kingside: {g4} and {h4}", goals: [Goal(piece: .p, to: "g4")]),
        PlanStep(text: "Knight to e5 supports the attack", goals: [Goal(piece: .n, to: "e5")]),
        PlanStep(text: "Keep the queenside closed"),
      ]),
  ],
  "iqp": [
    PlanVariant(id: "attack", name: "Attack", when: [.queens]),
    PlanVariant(
      id: "ending", name: "Ending", when: [.noQueens], headline: ("Trade off the weak pawn", "Win the d-pawn"),
      a: [
        PlanStep(text: "Rooks to the c- and e-files", check: .file("c")),
        PlanStep(text: "Push {d4–d5} to trade off the weak pawn", goals: [Goal(piece: .p, to: "d5")]),
        PlanStep(text: "Bring the king toward the center"),
      ]),
  ],
]

/// What a structure's own steps need, by structure, side and step.
let STEP_RULES: [String: (needs: [Need], check: StepCheck?)] = [
  "stonewall.a.1": ([.castledShort(.b), .queens], nil),
  "stonewall.a.2": ([.bishop(.a, light: true)], .keepBishop(light: true)),
  "stonewall.b.1": ([.bishop(.a, light: false), .bishop(.b, light: false)], .trade(light: false)),
  "carlsbad.a.0": ([.pawnFile(.a, "b"), .pawn(.b, "c6")], nil),
  "carlsbad.b.2": ([.bishop(.a, light: true), .bishop(.b, light: true)], .trade(light: true)),
  "french-chain.a.1": ([.pawnFile(.a, "f")], nil),
  "french-chain.a.2": ([.bishop(.a, light: false)], .keepBishop(light: false)),
  "french-chain.b.2": ([.bishop(.b, light: true)], nil),
  "caro-advance.a.0": ([.bishop(.b, light: true)], nil),
  "caro-advance.b.0": ([.bishop(.b, light: true)], nil),
  "czech-benoni.b.0": ([.pawnFile(.b, "f")], nil),
  "benoni.b.2": ([.bishop(.b, light: false)], .keepBishop(light: false)),
  "maroczy.b.2": ([.bishop(.b, light: false)], nil),
  "botvinnik.a.0": ([.piece(.a, .n)], nil),
  "botvinnik.b.0": ([.piece(.b, .n)], nil),
  "botvinnik.b.2": ([.piece(.a, .n)], nil),
  "sicilian-e5.a.0": ([.piece(.a, .n)], nil),
  "hedgehog.a.2": ([.castledShort(.b), .queens], nil),
  "central-tension.a.1": ([.piece(.a, .n)], nil),
  "dragon.a.0": ([.queens], nil),
  "dragon.a.1": ([], .castle(long: true)),
  "dragon.b.0": ([], .file("c")),
  "symmetrical.a.1": ([], .file("e")),
  "symmetrical.b.1": ([], .file("e")),
  "iqp.b.2": ([], .file("d")),
]

/// A structure's own steps for one side, with their rules.
func templateSteps(_ template: StructureTemplate, a side: Bool) -> [PlanStep] {
  let steps = side ? template.a : template.b
  return steps.enumerated().map { i, step in
    var out = step
    if let rule = STEP_RULES["\(template.id).\(side ? "a" : "b").\(i)"] {
      out.needs = rule.needs
      out.check = rule.check
    }
    return out
  }
}

/// A step placed for the board: its words, goals and shades turned when `a` is Black.
func placeStep(_ step: PlanStep, _ a: Color, _ me: Color) -> PlanStep {
  var out = step
  out.text = stepText(step.text, a, me)
  out.goals = step.goals?.map { Goal(piece: $0.piece, to: placeSquare($0.to, a)) }
  switch step.check {
  case .trade(let light)?: out.check = .trade(light: placeShade(light, a))
  case .keepBishop(let light)?: out.check = .keepBishop(light: placeShade(light, a))
  default: break
  }
  return out
}

/// The plan for the board, from your side. `kept` names the plan shown so far,
/// which stays while it still fits.
public func planOf(_ fen: String, _ me: Color, kept: String? = nil) -> Plan? {
  let facts = PlanFacts(fen)
  var candidates: [Plan] = []
  if let structure = structureOf(fen) {
    let template = structure.template, a = structure.a
    let variants = PLAN_VARIANTS[template.id] ?? [PlanVariant()]
    for variant in variants where variant.when.allSatisfy({ holds($0, facts, a: a) }) {
      let mine = a == me
      let raw = (mine ? variant.a : variant.b) ?? templateSteps(template, a: mine)
      // A step already out of reach is not offered; a plan with none left does not fit.
      let offered = raw.filter { step in
        step.needs.allSatisfy { holds($0, facts, a: a) } && markOf(placeStep(step, a, me), fen, facts, me: me, a: a) != .gone
      }
      if offered.isEmpty { continue }
      let headline = (variant.headline ?? PLAN_HEADLINES[template.id]).map { stepText(mine ? $0.a : $0.b, a, me) }
      let label = structureLabel(structure) + (variant.name.map { " · \($0)" } ?? "")
      candidates.append(Plan(
        key: "\(template.id):\(a.rawValue)" + (variant.id.map { ":\($0)" } ?? ""), label: label, headline: headline,
        steps: offered.map { placeStep($0, a, me) }, runs: offered.map { stepRuns($0.text, a, me) }, specificity: variant.when.count + 1, a: a))
    }
  }
  if let kept, let same = candidates.first(where: { $0.key == kept }) { return same }
  if let best = candidates.max(by: { $0.specificity < $1.specificity }) { return best }
  return genericPlan(fen, me, kept: kept)
}

/* ── plans from features ── */

/// One feature of the position and the step it asks for.
struct Feature {
  var id: String
  var label: String
  var headline: String
  var step: PlanStep
}

private let FILE_NAMES = Array("abcdefgh")

/// A plan built from what the position shows when no structure fits: up to three
/// steps, the most pressing first, named after the first.
func genericPlan(_ fen: String, _ me: Color, kept: String?) -> Plan? {
  var features = positionFeatures(fen, me)
  if let kept, kept.hasPrefix("generic:"), let i = features.firstIndex(where: { "generic:\($0.id)" == kept }) {
    features.insert(features.remove(at: i), at: 0)
  }
  let facts = PlanFacts(fen)
  features = features.filter { markOf($0.step, fen, facts, me: me, a: me) == nil }
  guard let first = features.first else { return nil }
  let steps = features.prefix(3).map(\.step)
  return Plan(
    key: "generic:\(first.id)", label: first.label, headline: first.headline,
    steps: steps.map { placeStep($0, .w, me) }, runs: steps.map { stepRuns($0.text, .w, me) }, specificity: 0, a: me)
}

/// The position's features that make a plan, the most pressing first.
func positionFeatures(_ fen: String, _ me: Color) -> [Feature] {
  let facts = PlanFacts(fen)
  let them = me.other
  let pawns = pawnFeatures(fen)
  let taken = Set(facts.men.map(\.square))
  var out: [Feature] = []
  func ahead(_ square: String, _ color: Color) -> String? {
    let (file, rank) = coords(square)
    let next = rank + forward(color)
    return (0..<8).contains(next) ? sq(file, next) : nil
  }

  let king = facts.king(me), theirKing = facts.king(them)
  if king == .center {
    let short = facts.canCastle(me, long: false), long = facts.canCastle(me, long: true)
    if short || long {
      out.append(Feature(
        id: "castle", label: "King in the center", headline: "Get the king safe",
        step: PlanStep(text: short ? "Castle short: {O-O}" : "Castle long: {O-O-O}", check: .castle(long: !short))))
    }
  }

  if facts.queensOn, king != .center, theirKing != .center, king != theirKing {
    let files = theirKing == .short ? [6, 7, 5] : [1, 0, 2]
    let push = files.lazy.compactMap { file -> String? in
      guard let pawn = facts.pawns(me, file: file).max(by: { rel(me, coords($0.square).rank) < rel(me, coords($1.square).rank) }),
        let to = ahead(pawn.square, me), !taken.contains(to)
      else { return nil }
      return to
    }.first
    if let push {
      out.append(Feature(
        id: "storm", label: "Opposite-side kings", headline: "Storm their king",
        step: PlanStep(text: "Storm their king: push {\(push)}", goals: [Goal(piece: .p, to: push)])))
    }
  }

  let passers = { (color: Color) in
    pawns.filter { $0.color == color && $0.passed }.sorted { rel(color, coords($0.square).rank) > rel(color, coords($1.square).rank) }
  }
  if facts.count(me, .n) > 0, let passer = passers(them).first, let stop = ahead(passer.square, them), !taken.contains(stop) {
    out.append(Feature(
      id: "blockade", label: "Their passed pawn", headline: "Blockade the passed pawn",
      step: PlanStep(text: "Blockade the passed pawn: knight to \(stop)", goals: [Goal(piece: .n, to: stop)])))
  }
  if let passer = passers(me).first, let to = ahead(passer.square, me), !taken.contains(to) {
    out.append(Feature(
      id: "passer", label: "Your passed pawn", headline: "Push the passed pawn",
      step: PlanStep(text: "Push the passed pawn: {\(to)}", goals: [Goal(piece: .p, to: to)])))
  }

  if facts.count(me, .n) > 0, let post = outposts(fen, me).first(where: { square in !facts.men.contains { $0.square == square && $0.color == me } }) {
    out.append(Feature(
      id: "outpost", label: "Outpost on \(post)", headline: "Knight to \(post)",
      step: PlanStep(text: "Knight to the \(post) outpost", goals: [Goal(piece: .n, to: post)])))
  }

  if facts.count(me, .r) > 0 {
    let order = [3, 4, 2, 5, 1, 6, 0, 7]
    let open = order.first { facts.fileFree(me, $0) && facts.fileFree(them, $0) && !facts.rook(me, file: $0) }
    let half = order.first { facts.fileFree(me, $0) && !facts.rook(me, file: $0) }
    if let file = open ?? half {
      let name = String(FILE_NAMES[file])
      let kind = open != nil ? "open" : "half-open"
      out.append(Feature(
        id: "file-\(name)", label: "\(open != nil ? "Open" : "Half-open") \(name)-file", headline: "Rooks to the \(name)-file",
        step: PlanStep(text: "Rooks to the \(kind) \(name)-file", check: .file(name))))
    }
    if let weak = pawns.first(where: { p in
      let file = coords(p.square).file
      return p.color == them && (p.isolated || p.backward) && facts.fileFree(me, file) && !facts.rook(me, file: file)
    }) {
      out.append(Feature(
        id: "weak-\(weak.square)", label: "Weak pawn on \(weak.square)", headline: "Hit the weak pawn",
        step: PlanStep(text: "Pile up on the weak pawn on \(weak.square)", check: .file(String(weak.square.first!)))))
    }
  }

  for light in [true, false] where facts.bishop(me, light: light) && facts.pawnsOn(me, light: light) >= 3 && facts.bishop(them, light: light) {
    let shade = light ? "light" : "dark"
    out.append(Feature(
      id: "bad-bishop", label: "Bad bishop", headline: "Trade the bad bishop",
      step: PlanStep(text: "Trade your \(shade)-squared bishop, hemmed in by your pawns", check: .trade(light: light))))
    break
  }
  return out
}
