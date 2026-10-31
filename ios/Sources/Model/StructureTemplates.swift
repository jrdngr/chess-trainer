import ChessCore

/// The named pawn structures, most specific first: `STRUCTURE_TEMPLATES` and
/// each template's test in `src/model/structures.ts`, written out by a script
/// from that file and `spec/constants.json`. A test keeps the data equal.

let TEMPLATES: [(template: StructureTemplate, test: @Sendable (Pawns, Color, Color) -> Bool)] = [
  (
    StructureTemplate(id: "stonewall", name: "Stonewall", sided: true,
      a: [PlanStep(text: "Plant a knight on e5, the square the wall was built for", goals: [Goal(piece: .n, to: "e5")]), PlanStep(text: "Attack the king: rook lift to the third rank, or {g4–g5}", goals: [Goal(piece: .p, to: "g4")]), PlanStep(text: "Keep the light-squared bishop pointed at the king")],
      b: [PlanStep(text: "Use the hole on e4: a knight lands there for good", goals: [Goal(piece: .n, to: "e4")]), PlanStep(text: "Trade the dark-squared bishops: the wall leaves those squares weak"), PlanStep(text: "Break with {c5} to open the queenside", goals: [Goal(piece: .p, to: "c5")])]),
    { p, a, _ in p.has(a, "c", 3) && p.has(a, "d", 4) && p.has(a, "e", 3) && p.has(a, "f", 4) }
  ),
  (
    StructureTemplate(id: "carlsbad", name: "Carlsbad", sided: false,
      a: [PlanStep(text: "Minority attack: {b4–b5} to hit c6 and leave a weak pawn", goals: [Goal(piece: .p, to: "b5")]), PlanStep(text: "Or play in the center with {f3} and {e4}"), PlanStep(text: "A knight on e5 supports either plan", goals: [Goal(piece: .n, to: "e5")])],
      b: [PlanStep(text: "Play on the kingside: {Ne4} and {f5}", goals: [Goal(piece: .n, to: "e4")]), PlanStep(text: "Meet <b5> by taking or by {c5} at the right moment"), PlanStep(text: "Trade the light-squared bishop that has no good square")]),
    { p, a, b in p.has(a, "d", 4) && p.none(a, "c") && p.has(b, "d", 4) && p.has(b, "c", 3) && p.none(b, "e") }
  ),
  (
    StructureTemplate(id: "french-chain", name: "French chain", sided: false,
      a: [PlanStep(text: "Hold d4: it is the base of the chain", goals: [Goal(piece: .n, to: "f3")]), PlanStep(text: "Use the kingside space: {f4–f5} to attack", goals: [Goal(piece: .p, to: "f5")]), PlanStep(text: "Keep the dark-squared bishop; it guards the holes")],
      b: [PlanStep(text: "Hit the base with {c5}", goals: [Goal(piece: .p, to: "c5")]), PlanStep(text: "Then hit the head with {f6}", goals: [Goal(piece: .p, to: "f6")]), PlanStep(text: "Trade off or free the light-squared bishop, the bad one")]),
    { p, a, b in p.has(a, "d", 4) && p.has(a, "e", 5) && p.has(b, "d", 4) && p.has(b, "e", 3) }
  ),
  (
    StructureTemplate(id: "caro-advance", name: "Caro-Kann Advance", sided: false,
      a: [PlanStep(text: "Use the kingside space; chase the bishop with {g4} or {h4}"), PlanStep(text: "Keep d4 solid against <c5>"), PlanStep(text: "Knight to f4 or e5 when it fits", goals: [Goal(piece: .n, to: "f4"), Goal(piece: .n, to: "e5")])],
      b: [PlanStep(text: "Get the light-squared bishop out before {e6}"), PlanStep(text: "Hit d4 with {c5}", goals: [Goal(piece: .p, to: "c5")]), PlanStep(text: "Then {e6} and pressure on d4 with the knights")]),
    { p, a, b in p.has(a, "d", 4) && p.has(a, "e", 5) && p.has(b, "c", 3) && p.has(b, "d", 4) && !p.has(b, "e", 3) }
  ),
  (
    StructureTemplate(id: "czech-benoni", name: "Czech Benoni", sided: false,
      a: [PlanStep(text: "Queenside: {a3} and {b4} to open lines", goals: [Goal(piece: .p, to: "b4")]), PlanStep(text: "Kingside space with {g3} and {f4}"), PlanStep(text: "Knight to b5 or d3", goals: [Goal(piece: .n, to: "b5"), Goal(piece: .n, to: "d3")])],
      b: [PlanStep(text: "Break with {f5}", goals: [Goal(piece: .p, to: "f5")]), PlanStep(text: "Knight to f4 if it can stay", goals: [Goal(piece: .n, to: "f4")]), PlanStep(text: "Keep the queenside shut with {a6} and {b6}")]),
    { p, a, b in p.has(a, "c", 4) && p.has(a, "d", 5) && p.has(a, "e", 4) && p.has(b, "c", 4) && p.has(b, "d", 3) && p.has(b, "e", 4) }
  ),
  (
    StructureTemplate(id: "kid-chain", name: "King's Indian chain", sided: false,
      a: [PlanStep(text: "Attack on the queenside: {c4–c5} to break", goals: [Goal(piece: .p, to: "c5")]), PlanStep(text: "Knights toward c5 via d3 or b3", goals: [Goal(piece: .n, to: "c5"), Goal(piece: .n, to: "d3"), Goal(piece: .n, to: "b3")]), PlanStep(text: "Answer <f5> calmly; keep the king safe first")],
      b: [PlanStep(text: "Storm the kingside: {f5}, {f4}, then {g5}", goals: [Goal(piece: .p, to: "f5")]), PlanStep(text: "Bring the knight round via {Ne8} or {Nh5}", goals: [Goal(piece: .n, to: "e8"), Goal(piece: .n, to: "h5")]), PlanStep(text: "Race: your attack must land before theirs on the queenside")]),
    { p, a, b in p.has(a, "d", 5) && p.has(a, "e", 4) && p.has(b, "d", 3) && p.has(b, "e", 4) }
  ),
  (
    StructureTemplate(id: "benoni", name: "Benoni", sided: false,
      a: [PlanStep(text: "Push {e4–e5} when it can be supported", goals: [Goal(piece: .p, to: "e5")]), PlanStep(text: "Knight to c4, hitting d6", goals: [Goal(piece: .n, to: "c4")]), PlanStep(text: "Stop <b5> with {a4}")],
      b: [PlanStep(text: "Queenside majority: {b5}", goals: [Goal(piece: .p, to: "b5")]), PlanStep(text: "Knight to e5, the outpost", goals: [Goal(piece: .n, to: "e5")]), PlanStep(text: "The long-diagonal bishop is your best piece; keep it")]),
    { p, a, b in p.has(a, "d", 5) && p.none(a, "c") && p.has(b, "c", 4) && p.has(b, "d", 3) && p.none(b, "e") }
  ),
  (
    StructureTemplate(id: "hedgehog", name: "Hedgehog", sided: false,
      a: [PlanStep(text: "Keep the space; stop <b5> and <d5> before anything else"), PlanStep(text: "Knight to d5 only when it cannot be taken", goals: [Goal(piece: .n, to: "d5")]), PlanStep(text: "Kingside expansion with {g4–g5} can work")],
      b: [PlanStep(text: "Wait behind the pawns, pieces ready"), PlanStep(text: "Break with {b5} or {d5} at the right moment", goals: [Goal(piece: .p, to: "b5"), Goal(piece: .p, to: "d5")]), PlanStep(text: "A knight on e5 or c5 hits the pawns", goals: [Goal(piece: .n, to: "e5"), Goal(piece: .n, to: "c5")])]),
    { p, a, b in p.has(a, "c", 4) && p.has(a, "e", 4) && p.none(a, "d") && p.none(b, "c") && p.has(b, "d", 3) && p.has(b, "b", 3) && p.has(b, "e", 3) }
  ),
  (
    StructureTemplate(id: "botvinnik", name: "Botvinnik setup", sided: false,
      a: [PlanStep(text: "Knight to d5, held by c4 and e4", goals: [Goal(piece: .n, to: "d5")]), PlanStep(text: "Kingside: {f4–f5} when ready", goals: [Goal(piece: .p, to: "f5")]), PlanStep(text: "Keep the long-diagonal bishop")],
      b: [PlanStep(text: "Hit the hole on d4", goals: [Goal(piece: .n, to: "d4")]), PlanStep(text: "Break with {b5} or {f5}", goals: [Goal(piece: .p, to: "b5"), Goal(piece: .p, to: "f5")]), PlanStep(text: "Trade the knight that wants d5")]),
    { p, a, _ in p.has(a, "c", 4) && p.has(a, "d", 3) && p.has(a, "e", 4) }
  ),
  (
    StructureTemplate(id: "maroczy", name: "Maróczy bind", sided: false,
      a: [PlanStep(text: "Squeeze: keep c4 and e4, knight on d5", goals: [Goal(piece: .n, to: "d5")]), PlanStep(text: "Expand on the queenside with {b4} and {c5}"), PlanStep(text: "Avoid trades: the side with less space wants them")],
      b: [PlanStep(text: "Trade pieces to ease the cramp"), PlanStep(text: "Break with {b5} or {f5}", goals: [Goal(piece: .p, to: "b5"), Goal(piece: .p, to: "f5")]), PlanStep(text: "Dark squares are yours: c5 and e5", goals: [Goal(piece: .n, to: "c5"), Goal(piece: .n, to: "e5")])]),
    { p, a, b in p.has(a, "c", 4) && p.has(a, "e", 4) && p.none(a, "d") && p.none(b, "c") && p.has(b, "d", 3) }
  ),
  (
    StructureTemplate(id: "dragon", name: "Dragon", sided: false,
      a: [PlanStep(text: "Open the h-file: {h4–h5} and trade the dark-squared bishop", goals: [Goal(piece: .p, to: "h5")]), PlanStep(text: "Castle long and race"), PlanStep(text: "Knight to d5 trades a key defender", goals: [Goal(piece: .n, to: "d5")])],
      b: [PlanStep(text: "Rook to c8 and the c-file; {Rxc3} is a common sacrifice"), PlanStep(text: "Knight to c4 or e5", goals: [Goal(piece: .n, to: "c4"), Goal(piece: .n, to: "e5")]), PlanStep(text: "Push {b5} to open lines on their king")]),
    { p, a, b in p.none(a, "d") && p.has(a, "e", 4) && p.none(b, "c") && p.has(b, "d", 3) && p.has(b, "g", 3) }
  ),
  (
    StructureTemplate(id: "scheveningen", name: "Scheveningen", sided: false,
      a: [PlanStep(text: "Kingside pawn storm: {g4–g5} against the knight", goals: [Goal(piece: .p, to: "g4")]), PlanStep(text: "Keep pressure on d6"), PlanStep(text: "Watch for <d5> and <e5> breaks")],
      b: [PlanStep(text: "Break in the center with {d5} or {e5}", goals: [Goal(piece: .p, to: "d5"), Goal(piece: .p, to: "e5")]), PlanStep(text: "Queenside counterplay: {b5} and the c-file", goals: [Goal(piece: .p, to: "b5")]), PlanStep(text: "Keep d6 defended")]),
    { p, a, b in p.none(a, "d") && p.has(a, "e", 4) && p.none(b, "c") && p.has(b, "d", 3) && p.has(b, "e", 3) }
  ),
  (
    StructureTemplate(id: "sicilian-e5", name: "Sicilian ...e5 (d5 hole)", sided: false,
      a: [PlanStep(text: "Knight to d5, the hole", goals: [Goal(piece: .n, to: "d5")]), PlanStep(text: "Trade the knight that guards d5"), PlanStep(text: "Queenside space with {a4} or {c4}")],
      b: [PlanStep(text: "Free your game with {d5}", goals: [Goal(piece: .p, to: "d5")]), PlanStep(text: "Guard d5 with pieces until you can"), PlanStep(text: "Kingside space with {f5} sometimes", goals: [Goal(piece: .p, to: "f5")])]),
    { p, a, b in p.none(a, "d") && p.has(a, "e", 4) && p.none(b, "c") && p.has(b, "d", 3) && p.has(b, "e", 4) }
  ),
  (
    StructureTemplate(id: "hanging-pawns", name: "Hanging pawns", sided: true,
      a: [PlanStep(text: "Push {c5} or {d5} at the right moment to free your pieces", goals: [Goal(piece: .p, to: "c5"), Goal(piece: .p, to: "d5")]), PlanStep(text: "Keep the pawns side by side; use the half-open files"), PlanStep(text: "Rooks behind the pawns")],
      b: [PlanStep(text: "Pressure c4 and d4 with your pieces"), PlanStep(text: "Make one advance, then blockade the square in front"), PlanStep(text: "Trades help you: the pawns grow weaker as pieces come off")]),
    { p, a, _ in p.has(a, "c", 4) && p.has(a, "d", 4) && p.none(a, "b") && p.none(a, "e") }
  ),
  (
    StructureTemplate(id: "iqp", name: "Isolated queen pawn", sided: true,
      a: [PlanStep(text: "Attack: pieces at the king, knight to e5", goals: [Goal(piece: .n, to: "e5")]), PlanStep(text: "Push {d4–d5} to open lines when it works", goals: [Goal(piece: .p, to: "d5")]), PlanStep(text: "Avoid trades: the endgame favors the other side")],
      b: [PlanStep(text: "Blockade d5 with a knight", goals: [Goal(piece: .n, to: "d5")]), PlanStep(text: "Trade pieces: the pawn gets weaker as they come off"), PlanStep(text: "Pressure d4 with rooks on the d-file")]),
    { p, a, _ in !p.none(a, "d") && p.none(a, "c") && p.none(a, "e") }
  ),
  (
    StructureTemplate(id: "big-center", name: "Big center", sided: false,
      a: [PlanStep(text: "Support the center; push {d5} or {e5} when it gains space", goals: [Goal(piece: .p, to: "d5"), Goal(piece: .p, to: "e5")]), PlanStep(text: "Develop behind the pawns"), PlanStep(text: "Do not let the center be undermined by <c5>")],
      b: [PlanStep(text: "Hit the center: {c5}, and the long-diagonal bishop", goals: [Goal(piece: .p, to: "c5")]), PlanStep(text: "Pressure d4 with knights"), PlanStep(text: "Provoke an advance, then blockade")]),
    { p, a, b in p.has(a, "d", 4) && p.has(a, "e", 4) && p.none(b, "d") && !p.has(b, "e", 4) }
  ),
  (
    StructureTemplate(id: "central-tension", name: "Central tension", sided: false,
      a: [PlanStep(text: "Keep the tension; {d4–d5} closes the center for good", goals: [Goal(piece: .p, to: "d5")]), PlanStep(text: "Knight route to f5 via d2 and f1", goals: [Goal(piece: .n, to: "f5")]), PlanStep(text: "Queenside space with {a4} or {c4}")],
      b: [PlanStep(text: "Hold e5; {exd4} gives up the center for activity"), PlanStep(text: "Kingside: {f5} if the center closes", goals: [Goal(piece: .p, to: "f5")]), PlanStep(text: "Knight to f4 if you get there", goals: [Goal(piece: .n, to: "f4")])]),
    { p, a, b in p.has(a, "d", 4) && p.has(a, "e", 4) && p.has(b, "d", 3) && p.has(b, "e", 4) }
  ),
  (
    StructureTemplate(id: "symmetrical", name: "Symmetrical center", sided: false,
      a: [PlanStep(text: "Outposts on e5 and e4 are the fight", goals: [Goal(piece: .n, to: "e5"), Goal(piece: .n, to: "e4")]), PlanStep(text: "The open e-file: rooks there first"), PlanStep(text: "A minority attack or {c4} break makes the imbalance", goals: [Goal(piece: .p, to: "c4")])],
      b: [PlanStep(text: "Same fight from the other side: e4 for your knight", goals: [Goal(piece: .n, to: "e4")]), PlanStep(text: "Rooks to the e-file"), PlanStep(text: "{c5} breaks the symmetry", goals: [Goal(piece: .p, to: "c5")])]),
    { p, a, b in p.has(a, "d", 4) && p.has(b, "d", 4) && p.none(a, "e") && p.none(b, "e") }
  ),
  (
    StructureTemplate(id: "open-center", name: "Open center", sided: false,
      a: [PlanStep(text: "Develop fast and get rooks to the open files"), PlanStep(text: "Pieces beat pawns here: activity first"), PlanStep(text: "Trade into an ending if your pawns are better")],
      b: [PlanStep(text: "Develop fast and get rooks to the open files"), PlanStep(text: "Pieces beat pawns here: activity first"), PlanStep(text: "Trade into an ending if your pawns are better")]),
    { p, _, _ in p.none(.w, "d") && p.none(.w, "e") && p.none(.b, "d") && p.none(.b, "e") }
  ),
]
