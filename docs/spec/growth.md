# Growth

Growth adds moves to your Playbook: it finds the replies your prep can't
meet, walks you to one, and you choose an answer from what strong players
play. The rows are `src/model/growth.ts`; a sitting is
`src/model/growthController.ts`. Autopilot's Grow this line plays one batch
of it (see the end screen area).

## Rows

**GROW-1** · port
A hole is a reply the opponent plays at least 1% of the time, in a position
your prep reaches with the opponent to move, that your prep does not answer,
within 18 plies of the start. A reply you kept in your repertoire with
nothing after it is a hole too, and counts at least the 15% prepared floor
for ranking.
Source: `growth.findHoles`, `growth.holeShare`, `prepFloor.PREPARED_FLOOR`; user-added-replies (10-02)
Cases: `growth.holeShare`, `growth.growthRows`, `const:DEFAULT_MIN_SHARE`, `const:DEFAULT_MAX_PLY`, `const:PREPARED_FLOOR`

**GROW-2** · port
Holes are grouped into rows by the family they lead into, named by the
shallowest book name past the first move. A row's urgency comes from the
depth of its shallowest hole first, then how often its top reply is played,
then a little for breadth. A starred opening's row counts ×1.6, capped at 1.
Rows are listed by that score.
Source: `growth.growthRows`, `growth.rowUrgency`, `growth.family`, `growth.STAR_BOOST`; growth-batch-scaling
Cases: `growth.growthRows`, `growth.rowUrgency`, `const:STAR_BOOST`

## A sitting

**GROW-3** · port
A sitting starts at the row's hole most worth answering (how often it is
reached times its share, the shallower on a tie), standing on the reply.
Source: `growthController.beginGrowth`, `growth.firstHole`; growth-starts-at-hole
Cases: `growth/answer-a-batch`, `growth/undo-one-and-all`, `e2e:growth-session`

**GROW-4** · port
A batch is measured at its first hole: half the plies left to 18, at least
one and at most eight answers.
Source: `growthController.measureBatch`, `growth.addsToFit`; growth-batch-scaling
Cases: `growth.addsToFit`, `growth.movesToFit`, `growth/answer-a-batch`, `const:MAX_ADDS`

**GROW-5** · port
At a hole you are offered the book's answers, most played first, up to four.
Choosing one saves the line through it to your Playbook (with their reply
when the reply was not saved yet), logs the pick with what was offered, and
says "<move> added".
Source: `growthController.choose`, `growth.choicesAt`, `growth.lineFor`
Cases: `growth/answer-a-batch`, `growth.choicesAt`, `growth.optionsAt`

**GROW-6** · port
After your answer, the opponent plays the book's most played reply, and the
run stands on it as the next hole. With no reply at all, the batch is over.
The answer that fills the batch brings the run to rest instead.
Source: `growthController.theyReply`, `growth.nextHole`
Cases: `growth/answer-a-batch`, `growth/to-the-edge-of-the-book`

**GROW-7** · port
A hole where the book has no answer to offer ends the batch rather than
waiting there. Done ends it by hand.
Source: `growthController.stop`
Cases: `growth/answer-a-batch`

**GROW-8** · port
Undo takes the last answer of the sitting back out: its move leaves the
Playbook (with the reply it answered when that was added with it), and the
run stands on the reply again with the batch as it was. Undo all takes every
answer of the sitting back. Undo never reaches moves from before the sitting.
Source: `growthController.undo`; growth-undo
Cases: `growth/undo-one-and-all`

**GROW-9** · port
At rest, another batch starts from where the line now ends: at the hole the
run stands on, or at the book's reply to your last answer. When the book has
nothing more there, no batch is offered.
Source: `growthController.anotherBatch`, `growth.resumeAdding`; growth-reveal-analyze
Cases: `growth/answer-a-batch`, `growth/to-the-edge-of-the-book`

**GROW-10** · port
Growth stops where the book does: standing at a position the book has no
reply for, the run comes to rest and flashes "End of the book".
Source: `growthController.reachedEdge`, `growth.pastTheBook`; openings-without-extensions (10-23)
Cases: `growth/to-the-edge-of-the-book`, `growth.pastTheBook`

**GROW-11** · port
A row with no holes starts at its line end most often reached; with neither,
the run walks your prep from move one, the opponent steering toward the
row's holes. While walking, a move your prep doesn't have loses the run.
Source: `growthController.beginGrowth`, `growthController.walk`, `growthController.opponentWalks`
Cases:

**GROW-12** · port
A sitting is one round, whatever it takes, logged against the deepest opening
its line reached. It counts as perfect when the batch was filled.
Source: `growthController.growthRound`
Cases: `growth/answer-a-batch`, `growth/undo-one-and-all`, `growth/to-the-edge-of-the-book`

**GROW-13** · port
Each answer shows what it does to the eval bar, from your side, in pawns:
0.0 under 10cp, capped at 9.9, toned good, bad or even. Mates count as
100000 less the moves to mate. Answers listed in the engine's order go best
shown delta first, ties to the more played, moves not yet weighed last in the
order they came; in strong players' order, most played first and ties to the
engine.
Source: `evalDelta.deltaFor`, `evalDelta.formatDelta`, `evalDelta.byDelta`, `evalDelta.byShare`
Cases: `evalDelta.deltaFor`, `evalDelta.whiteCp`, `evalDelta.order`, `const:EVEN_CP`

## Conflicts for the owner

- **GROW-11** has no case because no row reached it in testing: every row
  `growthRows` returned had a hole, and no fixture produced a row with only
  line ends, or with neither. The walking start and the line-end start may be
  unreachable now that sittings start at a hole; if so they are candidates for
  drop.
