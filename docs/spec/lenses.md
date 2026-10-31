# Lenses, plans and Cash out

Help for the middlegame, read from the board. The lenses are
`src/model/boardHints.ts` and `src/components/Lenses.tsx`; structures and
plans are `src/model/structures.ts` and `src/components/PlanCards.tsx`; the
engine-backed parts are `src/engine/pawnBreaks.ts` and
`src/engine/cashOut.ts`, on a second engine of their own (`hintEngine.ts`).

## The lens bar

**LENS-1** · port
Under the board in Survival (and Autopilot's runs), on Survival's end screen,
and in Analysis there is a bar of five lenses: Pawns, Pieces, Space, Kings,
Threats. Holding one shows it over the position; letting go anywhere clears
it. Lenses are read from the board alone, from the side you play ("mine"
blue, "theirs" red), so a mark can be checked by looking, and can be used at
any time, prep included. The engine is asked only for the Pawns lens's
breaks, on the hints' own engine so the game's never waits.
Source: `Lenses.useLens`, `boardHints.LENSES`, `hintEngine.hintSearch`; middlegame-brainstorm (10-10)
Cases: `boardHints.lensMarks`, `const:LENSES`, `e2e:survival-runs`

**LENS-2** · port
Pawns fades every piece but the pawns. A passed pawn (no enemy pawn ahead on
its file or the next) is tagged good; an isolated, doubled or backward pawn
is tagged bad (backward: its neighbors have all gone past it and an enemy
pawn guards the square in front). Holes are dotted: squares on a side's third
and fourth ranks, b to g files, that none of its pawns can ever attack again.
The caption names the structure. Each side's best pawn break (a pawn capture,
or a push that attacks a pawn) is drawn as an arrow when the engine rates it
within 150cp of that side's best move.
Source: `boardHints.pawnsLens`, `boardHints.pawnFeatures`, `boardHints.holes`, `boardHints.breakCandidates`, `pawnBreaks.pawnBreaks`
Cases: `boardHints.lensMarks`, `boardHints.breakCandidates`

**LENS-3** · port
Pieces tints each knight, bishop, rook and queen by its safe squares (not its
own men's, not guarded by an enemy pawn) against what is typical (knight 5,
bishop 6, rook 7, queen 13): green from 90%, amber from 45%, else red. Each
side's worst piece is ringed. Outposts are starred: squares on a side's
fourth to sixth ranks, b to g files, that no enemy pawn can ever attack and
one of its own pawns guards. Your knights' shortest routes (at most three
hops) to your two nearest outposts are drawn.
Source: `boardHints.piecesLens`, `boardHints.activity`, `boardHints.outposts`
Cases: `boardHints.lensMarks`

**LENS-4** · port
Space tints every attacked square by who holds it: yours blue and theirs red,
deeper by the margin of attackers (up to 3); an even fight is purple, leaning
blue or red to the side whose cheapest attacker is cheaper. Attacks count
through a friendly piece moving the same way (doubled rooks both count). The
caption counts the squares each side holds outright in the other's half,
"Space · you 6 – 1 them".
Source: `boardHints.spaceLens`, `boardHints.control`, `boardHints.spaceCount`
Cases: `boardHints.lensMarks`, `boardHints.spaceCount`

**LENS-5** · port
Kings outlines each king's zone (the squares round it, two ranks out in
front), marks the zone squares under attack with attackers and defenders,
marks missing shield pawns in front of a king still on its first two ranks,
and draws open files beside it (when the enemy has a rook or queen) and
enemy bishops or queens on its forward diagonals. Score: attacks + 2 per
missing shield pawn + 2 per line − half the defenders; in check or 7 and up
is Under attack, 3 and up Exposed, else Safe. Caption: "You: Safe · Them:
Under attack".
Source: `boardHints.kingsLens`, `boardHints.kingReport`, `boardHints.KING_GRADE_TEXT`
Cases: `boardHints.lensMarks`, `boardHints.kingReport`, `const:KING_GRADE_TEXT`

**LENS-6** · port
Threats rings every man that is hanging (attacked and undefended, or a king
in check) in red, and every one attacked by something cheaper in amber. On
your turn it also draws what the opponent's last move newly threatens. The
caption is "Nothing hanging" or "Yours at risk 2 · theirs 1".
Source: `boardHints.threatsLens`, `boardHints.loosePieces`, `boardHints.newThreats`
Cases: `boardHints.lensMarks`

**LENS-7** · port
The Undefended flash, a Survival setting off by default (and off in
Autopilot): a move that leaves any of your men newly loose is held for 1.3s
with those men ringed and a Take back button; untouched, it lands.
Source: `SurvivalScreen.onMove`, `boardHints.newlyLoose`, `survival.DEFAULT_SURVIVAL`
Cases: `boardHints.newlyLoose`

## Plans

**LENS-8** · port
The pawns are matched against 19 named structures (the IQP, Carlsbad,
Stonewall, King's Indian chain, Maróczy bind, French chain, Hedgehog and
the rest), most of them owned by one side, "Isolated queen pawn (White)".
Each has a few plain-words steps for each side, written for White and
mirrored when Black owns it, with Black's moves given their "...".
Source: `structures.structureOf`, `structures.structureLabel`, `structures.planFor`, `structures.stepText`
Cases: `structures.structureOf`, `structures.planFor`, `const:STRUCTURE_TEMPLATES`

**LENS-9** · port
Past the end of prep in a run, and always in Analysis, a Plan row under the
board names the structure; tapping it lists your side's steps, each ticked
once a piece of the kind it names stands on its square. The plan is words
only and draws nothing: plan steps are rules of thumb, not checked by the
engine. The × hides it until the structure changes or a new run starts.
Source: `PlanCards.usePlanCard`, `boardHints.goalRoute`; plan-hints-no-moves (10-20)
Cases: `boardHints.goalRoute`, `e2e:survival-runs`

## Cash out

**LENS-10** · port
In a run past the prep, on your turn, when you are 200cp or more ahead, the
engine's best four moves are searched for a trade: the first within 30cp of
the best, still 200 ahead, that captures a piece (not a pawn, not with the
king) which is taken straight back by a piece within one point of its value.
A Cash out row then reads "Ahead: trade down?", and open, "Trade with Bxf6",
with the trade drawn in green. Its × hides it for the rest of the run.
Source: `cashOut.pickTrade`, `PlanCards.useCashOutCard`, `SurvivalScreen`
Cases: `cashOut.pickTrade`

## Conflicts for the owner

None found so far in this area.
