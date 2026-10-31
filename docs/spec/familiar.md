# Familiar moves

How the app judges which of your possible moves is closest to the lines you
already have. It colors Growth's arrows, finds Tidy's switches, and words the
end screen's off-prep hint. The rules are `src/model/nudge.ts` (with
`kin.ts` and `setups.ts`), Tidy is `src/model/tidy.ts`, and Growth's answer
arrows are `src/model/answerArrows.ts`.

## What makes a move familiar

**FAM-1** · port
A move is judged against your other lines: the positions on the line so far
(and, for Tidy, those only your own move's subtree reaches) never count for
or against it. Your first move of the game picks the opening and is never
judged.
Source: `nudge.signalsFor`, `nudge.isFirstMove`, `nudge.goneWith`
Cases: `nudge.nudgeArrows`, `tidy.scan`

**FAM-2** · port
A move transposes when it lands on one of your positions (strength 1), or can
transpose when the book's replies at or above the minimum share land on one,
for at least 25% of games (strength is that share). It heads toward your
lines when, for at least 25% of games, the reply and then one more move of
yours land on one.
Source: `nudge.signalsFor`, `nudge.VIA_REPLY_MIN`
Cases: `nudge.nudgeArrows`, `const:VIA_REPLY_MIN`

**FAM-3** · port
A habit is a move you chose at other positions within 4 plies of this depth,
in this opening and its kin, at least 2 times and at least as often as you
passed it up. Passing it up means the book offered it there (at the minimum
share) and you chose something else, unless your line plays it within your
next two moves. Check, capture and annotation marks are ignored (Nxe5 is
Ne5). Failing the move itself, the setup it belongs to (fianchetto, London
and the like) counts the same way within 8 plies, so g3 counts your Bg2s.
Source: `nudge.contextOf`, `nudge.habitVia`, `nudge.sameMove`, `nudge.HABIT_PLIES`, `nudge.HABIT_MIN`, `setups.ts`; off-prep-edit-and-consolidate
Cases: `nudge.sameMove`, `nudge.nudgeArrows`, `const:HABIT_MIN`, `const:HABIT_PLIES`, `const:SETUPS`

**FAM-4** · port
Kin sets let habits carry across related openings, so a new Catalan already
knows your English's g3. A family's kin is itself and every family that
shares a kin set with it.
Source: `kin.KIN_SETS`, `kin.kinOf`
Cases: `kin.kinOf`, `kin.KIN_SETS`, `const:KIN_SETS`

**FAM-5** · port
With "your usual pawns" on, a move that changes your pawns into a structure
your lines in this opening have counts as a weaker familiarity.
Source: `nudge.signalsFor` (pawns)
Cases: `nudge.nudgeArrows`

**FAM-6** · port
Familiarity is read in the priority's order: Transposition first is
transposes, heads toward, habit, pawns; Habit first is habit, pawns,
transposes, heads toward. The first kind any move scores in wins, the
strongest move in it, and on a tie the more played one.
Source: `nudge.towardOrder`, `nudge.pickToward`, `modes.DEFAULT_GROWTH`
Cases: `nudge.nudgeArrows`

## Working against your lines

**FAM-7** · port
A move closes off a line of yours when the line ends deeper and the move makes
its last position unreachable: pawns only go forward (sideways only by
capturing), captured pieces stay gone, and lost castling rights stay lost.
Castling never closes anything, and a line another of your moves at this
position still reaches is not closed by this one. A move is passed up when you
passed it up at least 2 times and more often than you chose it, and it is not
part of a setup you use. Transposition first asks closes off before passed up;
Habit first the reverse. The strongest wins, and on a tie the less played one.
Source: `nudge.reachable`, `nudge.awayStrength`, `nudge.pickAway`
Cases: `nudge.reachable`, `nudge.nudgeArrows`

## Growth's arrows

**FAM-8** · port
At a position you are answering, the most familiar move goes green with its
reason and a pill. If it is not already drawn it goes on the board yellow:
alongside the others in Growth, otherwise in place of the same piece's arrow,
else the third. Of the moves still drawn plain, the one that works most
against your lines goes red. Reasons: "d4 transposes into your Normal
Variation line", "e6 can transpose into your …", "… heads toward your …",
"You play g3 in 3 English and Catalan lines", "You fianchetto in 3
English lines" for a setup, "d5 reaches your usual French pawns", "c5 closes off 2
of your Queen's Gambit Declined lines", "You've chosen another move over Nf3
7 times in your … lines". Pills: Transposes, Can transpose, Heads toward,
Your habit, Your setup, Your pawns, Closes off, Breaks a habit. A line is
named by its deepest name without the family; families by their short name,
the two that gave most.
Source: `nudge.nudgeArrows`, `nudge.towardReason`, `nudge.towardPill`, `nudge.awayReason`; repertoire-nudge-arrows
Cases: `nudge.nudgeArrows`, `nudge.nudgeArrows (append)`

**FAM-9** · port
Legal moves the book leaves out, or ranks under the minimum share, are asked
about too and kept when familiar. The engine must pass one before it can be
shown; it then reads "· not in the book".
Source: `nudge.familiarOffBook`, `engine/soundness.ts`, `GrowthScreen`
Cases: `nudge.familiarOffBook`, `nudge.nudgeArrows (append)`, `const:NOT_IN_BOOK`

**FAM-10** · port
Growth's answer arrows show who recommends each move: blue for the reply
strong players choose most, then the engine's best two by eval, purple and
lighter purple. When strong players and the engine agree, the move stays blue
and the engine's next takes its place. Until the engine has weighed any move
only blue is drawn. Past the book there are no shares, and all three are the
engine's, in the order given until weighed.
Source: `answerArrows.roleArrows`; growth-castling-and-eval (10-29)
Cases: `answerArrows.roleArrows`, `const:ROLE_ARROWS`

## Tidy

**FAM-11** · port
A Tidy scan looks at every position you chose at inside the selection, one per
side, with a transposition looked at once. At each it compares your move with
the book's moves at the minimum share and your off-book habits, leaving out
your other moves there. It finds a switch when another move is more familiar
(earlier kind in the priority, then stronger). A habit is only a reason to
switch when your move is a habit nowhere and is not a capture; the reason then
adds ", Nc3 in none". A find is green when the board would draw the move
anyway and yellow when it is pulled in, and it says why your move works
against your lines when it does. Finds removing the most moves come first,
then the earliest. An off-book switch waits on the engine.
Source: `tidy.tidyPositions`, `tidy.findAt`, `tidy.sortFinds`, `nudge.bestSwitch`, `nudge.againstReason`, `TidyScreen`; off-prep-edit-and-consolidate
Cases: `tidy.scan`

**FAM-12** · port
A find has one action, "Switch · removes N moves". The new move becomes yours
and preferred there, and your old move goes with everything under it, marked
as a Tidy switch. The position's card starts over and the misses logged at it
go; the rating stands. Undo puts it all back. With nothing found the screen
says "Nothing to tidy in <selection>".
Source: `tidy.switchMove`, `useStore.tidySwitch`, `TidyScreen`
Cases: `tidy.switchMove`, `tidy.moveLabel`

**FAM-13** · port
On the end screen, a miss whose played move is closer to the rest of your
lines than the prepared one gets a green reason and "Tidy this", which opens
Tidy on that position. For the move played over the board, a habit needs no
test against the times you passed it up.
Source: `tidy.offPrepHint`, `End.tsx`, `OffPrepHint.tsx`
Cases: `tidy.offPrepHint`

## Conflicts for the owner

None found so far in this area.
