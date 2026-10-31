# A run

A Survival run, which is also every Autopilot round. The rules here are the
run controller's (`src/model/survivalController.ts`) and the functions it
calls in `src/model/survival.ts`. Starts, the recommendation and the end
screen are their own areas.

## The run and your prep

**RUN-1** · port
A run begins on prep, with nothing answered, no book phase, no extras and no
ending. The prompt shows no prep status until your prep has answered something,
unless your prep has a move in the position in front of you.
Source: `survivalController.beginSession`, `prepLabel`
Cases: `survival/clean-prep-into-the-book`, `survival/mated-as-black`

**RUN-2** · port
Your prep at a position is every move your repertoire answers it with, found by
position, so a transposition counts.
Source: `survivalController.prepMoves`, `survival.prepHere`
Cases: `survival/clean-prep-into-the-book`, `survival/miss-then-moments-and-a-blunder`

**RUN-3** · port
Playing a prepared move reviews that position's card, graded by how long the
move took (`srs.gradeForTime`), and adds one rated result, correct, for the
position you were asked. The move is played, and it earns one point at ×1.
Source: `survivalController.playPrepared`, `survival.playYours`, `survival.prepExtras`; rating-per-opening (09-21)
Cases: `survival/clean-prep-into-the-book`, `srs.gradeForTime`, `survival.prepExtras`

**RUN-4** · port
A rated result is credited to the position asked, not where the move went. It
carries `ext` when the move is past where the line left the book, and is not
rated at all when the move is saved as a mistake (its card is still reviewed).
Source: `survivalController.tally`; extensions-design (10-24)
Cases: `survival/saved-mistake-in-prep`, `survival/clean-prep-into-the-book`

**RUN-5** · port
In Autopilot, a prepared move pops a tick and its time over its square, in the
grade's color (`survival.speedTone`), written as `survival.secondsText` says.
A prepared move past the book is outlined as an extension ("Ext").
Source: `survivalController.playPrepared`; autopilot-naming (10-23)
Cases: `survival/clean-prep-into-the-book`, `survival.speedTone`, `survival.secondsText`

**RUN-6** · port
A prepared move saved as a mistake pops its cost instead, in red, when the
engine has said what it gives away.
Source: `survivalController.playPrepared`; extensions-design (10-24)
Cases: `survival/saved-mistake-in-prep`

**RUN-7** · port
Your turn with nothing prepared, having followed your prep so far, completes
the prep. With no miss in the run, the line as it stands is the clean finish
and where growing would start, even if the prep asked nothing. Prep status is
latched: once complete or off, it stays so for the run.
Source: `survivalController.prepRanOut`; grow-from-autopilot (10-25)
Cases: `survival/clean-prep-into-the-book`, `survival/saved-mistake-in-prep`

## The book phase

**RUN-8** · port
Where a clean prep completes in a position the book has, the book phase
begins; where the book has nothing, the run is out of book at once. The prompt
reads "In the book" during the phase and "Out of book" after it.
Source: `survivalController.prepRanOut`, `prepLabel`; openings-without-extensions (10-23)
Cases: `survival/clean-prep-into-the-book`, `survival/saved-mistake-in-prep`

**RUN-9** · port
During the book phase, a move the engine passes is a book move when strong
players play it at least 5% of the time here and it gives away no more than
40cp. A book move moves the phase on and counts toward the run's book moves.
Any other move ends the phase.
Source: `survival.isBookMove`, `survival.bookMoves`
Cases: `survival/clean-prep-into-the-book`, `const:BOOK_SHARE`, `const:SCORE_SLIGHT`

**RUN-10** · port
The book phase also ends on your turn when the book has nothing for the
position, whoever left it.
Source: `survivalController.closeBook`, `bookRanOut`
Cases: `survival/book-runs-out`

**RUN-11** · port
In Autopilot a book move pops a tick, its time and "Book" in the book's color,
instead of a score. A book move keeps the combo going whatever the engine
prefers, and it is never rated and never reviews a card.
Source: `survivalController.judgedMove`
Cases: `survival/clean-prep-into-the-book`, `survival/book-runs-out`

## Misses and judged moves

**RUN-12** · port
A move your prep doesn't have, where it has one, is a miss: a rated result,
wrong, for the position asked, and logged for review with the move played and
the prepared one. Prep status goes off, there is no clean finish for the run,
and the prepared move is drawn as a green arrow for 2s.
Source: `survivalController.judgedMove`; survival-mode-redesign (09-25)
Cases: `survival/miss-then-moments-and-a-blunder`, `e2e:survival-runs`

**RUN-13** · port
A move the engine calls a blunder ends the run, whether it was a miss or past
your prep. The move is not played; the ending keeps it, the engine's best move,
what it lost, and the opponent's best answer as the threat.
Source: `survivalController.judgedMove`; survival-blunder-check, blunder-threat-arrow (10-26)
Cases: `survival/miss-then-moments-and-a-blunder`, `const:BLUNDER_LIMIT`

**RUN-14** · port
A sound judged move is played. With move scores on, it pops what it changed
since your last scored move (`survival.evalSwing`, `survival.moveScore`),
never as a score of 0.
Source: `survivalController.judgedMove`; survival-move-scores-glow (09-27)
Cases: `survival/miss-then-moments-and-a-blunder`, `survival.evalSwing`, `survival.moveScore`, `survival/ended-on-prep-quietly`

**RUN-15** · port
A judged move steps the extras: the combo, its points, a moment settled, a
mission stepped or set (see `survival.judgedExtras`). Moments count only past
your prep. What it earned is said over the board in one note: a moment found
or missed (with the move that was there), a mission done or failed, or the
combo broken.
Source: `survivalController.judgedMove`, `noteFor`; growth-past-book-warning (10-10)
Cases: `survival/miss-then-moments-and-a-blunder`, `survival.judgedExtras`, `survival.comboAfter`, `survival.momentBonus`

**RUN-16** · port
A missed moment draws the move that was there, while its note shows.
Source: `survivalController.judgedMove`
Cases: `survival/miss-then-moments-and-a-blunder`

**RUN-17** · port
Where the prep runs out, the first mission is set from the eval in front of
you: the structure's plan when the pawns form one with a square in reach,
otherwise from the eval.
Source: `survivalController.missionFrom`, `survival.firstMission`
Cases: `survival.firstMission`, `survival.planMission`, `survival.missionFor`, `survival/clean-prep-into-the-book`

## The line drawn

**RUN-22** · port
A run's line is drawn up front and only steers the opponent; any move inside
the region is accepted at your turn whichever line was drawn. My lines draws
one of your own lines through the region, by how often you would meet it
(Autopilot's popular lean) or tilted toward the positions you answer worst
(weak, the default from the setup screen). My gaps draws the way to a reply
you have no answer to. Ignore my lines draws on the book alone and keeps your
prep only to know where you missed. Failing all of these the line is the
region's own move order. Random side is settled once, up front. Every draw
comes from the run's seed through one generator (mulberry32), in a fixed
order, so a seed replays the same run.
Source: `openingRun.beginRun`, `survival.startSurvival`, `openingRun.resolveColor`
Cases: `survival.startSurvival (draw)`, `openingRun.resolveColor`, `survival/clean-prep-into-the-book`

**RUN-23** · port
How often each of your lines comes up: where the opponent chooses, by how
often strong players choose each move, every prepared reply getting at least
the prepared floor (15%) of the position; where you choose between your own
moves, evenly, so a heavily branched line of yours does not swamp the rest.
Lines the run cannot use are dropped before the split, so their share goes to
the lines that remain.
Source: `openingRun.lineOdds`, `prepFloor.withFloor`
Cases: `openingRun.lineOdds`, `survival.startSurvival (shares)`, `const:PREPARED_FLOOR`

**RUN-24** · port
Weak leans by each line's mean appetite over its positions: a position never
studied 1.5; one with a card 1, plus 1.2 a lapse, twice how far its ease is
under 2.5, 1 while learning, 1 when due, and twice its wrong share; plus 2 for
each game your games went off prep there, up to 3 games.
Source: `openingRun.weaknessFromCards`, `openingRun.lineWeakness`
Cases: `openingRun.weaknessFromCards`, `openingRun.lineWeakness`

**RUN-25** · port
Among your lines the one left longest is preferred, and the line the last
round was drawn on is not drawn at all while there is another. A position
counts as unseen 3 rounds after it was last seen. A line is read in two
parts: its tail, from the last place it parts from another of your lines,
and its head before that; its freshness is the tail's mean staleness times
half plus half the head's. So the same line twice running is stale, and a
different variation of the same opening is half fresh.
Source: `freshness.lineStaleness`, `freshness.justRun`, `freshness.lineParts`, `scoring` (marks each round's line seen)
Cases: `survival.startSurvival (fresh)`, `freshness.staleness`, `freshness.lineParts`, `freshness.lineStaleness`, `const:HORIZON`, `const:HEAD_WEIGHT`

**RUN-26** · port
Starting inside an opening plays the drawn line's way in for you: its moves up
to the first that reaches a position the opening names. A line that never
gets there starts from move one.
Source: `openingRun.wayIn`, `openingRun.beginRun` (enter)
Cases: `openingRun.wayIn`, `survival.startSurvival (draw)`

## The opponent

**RUN-18** · port
The opponent plays from the book while it has a move: along the line drawn for
the run, redrawn by the same steer when you have stepped off it; then by
popularity among moves of at least 5%. Where the book has nothing, the engine
plays.
Source: `survivalController.bookTurn`, `survival.bookReply`, `engineMove`
Cases: `survival/clean-prep-into-the-book`, `survival/saved-mistake-in-prep`

**RUN-27** · port
Off the drawn line the opponent replies at random by weight, among the
replies after which the run can still go on where there are any. Past the
prep, a move of yours that gives away more than 80cp (from your side, never
less than nothing) is a blunder.
Source: `openingRun.opponentReply`, `openingRun.judgeByEval`
Cases: `openingRun.opponentReply`, `openingRun.judgeByEval`, `const:BLUNDER_LIMIT`

## The end

**RUN-19** · port
Mate or a draw on the board ends the run as won, lost or drawn.
Source: `survivalController.afterMove`
Cases: `survival/mated-as-black`

**RUN-20** · port
You can end a run yourself at any time, from move one. It is counted apart
from moves survived.
Source: `survivalController.endRun`; survival-end-run (10-31)
Cases: `survival/clean-prep-into-the-book`, `survival/ended-on-prep-quietly`

**RUN-21** · port
A run ends once. The end carries how it ended, the run as it stood, the clean
finish when there was no miss, whether it was a stub (a clean finish where the
prep asked nothing), and the run's rated answers. After it, a late verdict or
move changes nothing.
Source: `survivalController.finish`
Cases: `survival/mated-as-black`, `survival/clean-prep-into-the-book`

## Conflicts for the owner

None found so far in this area.
