# Drill

Drill asks your prep out of a game: positions one at a time, or whole lines
from move one. Positions are `src/model/drillController.ts`; lines are
`src/model/lineDrillController.ts`. Drill is recorded but never rated.

## Positions

**DRILL-1** · port
A sitting lines up 20 positions at a time: scheduled work first (due cards,
then up to the session's new ones), led by a position with a way in. With
Weakest first on, the ones you keep getting wrong come before what is merely
due.
Source: `drillController.beginDrill`, `session.buildSession`, `session.leadWithAWayIn`, `session.weakestFirst`
Cases: `drill/positions-a-sitting`, `const:BATCH`

**DRILL-2** · port
The queue is topped up once 6 or fewer positions are left: scheduled work
first, then the stalest positions as extra practice, so a sitting only ends
when you end it.
Source: `drillController.refill`, `session.extraPractice`
Cases: `drill/positions-a-sitting`, `const:REFILL_AT`

**DRILL-3** · port
A right answer (any move your prep has there) is graded by its time
(LEARN-4), recorded unrated, and shown for a beat before the next position.
Following the line, the next position is the next decision point down it:
your answer, their reply, and the position after.
Source: `drillController.answer`, `drillController.followUpFor`, `drillController.advance`
Cases: `drill/positions-a-sitting`, `e2e:drill-sessions`

**DRILL-4** · port
A wrong answer is graded Again at once and logged as a mistake with the move
expected. Continue sends the position back 4 positions on.
Source: `drillController.answer`, `drillController.continueAfterWrong`
Cases: `drill/positions-a-sitting`, `const:REQUEUE_AFTER`, `e2e:drill-sessions`

**DRILL-5** · port
The grade buttons stay up for the next position and change the last right
answer's grade: its card goes back to how it was and takes the new grade.
Guessed (Again) also sends it back 4 positions on.
Source: `drillController.regradeLast`
Cases: `drill/positions-a-sitting`, `e2e:drill-sessions`

**DRILL-6** · port
A sitting is logged as one round, against the opening it was played in, and
only with something answered. It is perfect with every answer right and at
least five of them.
Source: `drillController.drillRound`
Cases: `drill/positions-a-sitting`, `e2e:drill-sessions`

## Lines

**DRILL-7** · port
A line is played from move one: the opponent's moves play themselves, and
each of yours is asked. Another move your prep has is right too, and the line
follows it from there.
Source: `lineDrillController.theirMove`, `lineDrillController.answer`, `lineDrill.continueLine`
Cases: `drill/lines-a-group`, `e2e:drill-sessions`

**DRILL-8** · port
A right move is recorded and shown for a beat, and clears a mistake logged at
that position. A miss is recorded, counted against the line and logged as a
mistake; Continue plays your prep's move and the line goes on.
Source: `lineDrillController.answer`, `lineDrillController.carryOn`
Cases: `drill/lines-a-group`

**DRILL-9** · port
At the end of a line it is logged as a round of its own, perfect with no
miss, and its line card is graded once, for you, by `srs.gradeForLine`.
Tapping another grade puts the card back and grades it again.
Source: `lineDrillController.lineDone`, `lineDrillController.regrade`; line-drill-grades (10-03)
Cases: `drill/lines-a-group`, `srs.gradeForLine`

**DRILL-10** · port
Lines come in groups of similar lines; when a group is played out, a fresh
group is drawn, avoiding the lines just played.
Source: `lineDrillController.nextLine`, `lineDrillController.needsDraw`, `lineDrill.drawLines`
Cases: `drill/lines-a-group`

## Conflicts for the owner

None found so far in this area.
