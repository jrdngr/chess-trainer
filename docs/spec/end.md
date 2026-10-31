# The end of a run

What happens once a run is over: what is logged, the end screen, and its one
way into Growth. The run's own ending rules are in [run.md](run.md) (RUN-19
to RUN-21).

## What is logged

**END-1** · port
A run is logged as one round, against the deepest opening its line reached
in the region it was drawn from. It counts a blunder as an answer that was
not right. It is perfect when the prep was played to its end without a miss
and was not a stub; its line is then the line finished, otherwise the line
the opponent was steering toward. It carries the prepared positions asked and
found, which is what prep accuracy reads (AUTO-12).
Source: `survivalController.runRound`; grow-from-autopilot (10-25)
Cases: `survival/clean-prep-into-the-book`, `survival/miss-then-moments-and-a-blunder`, `survival/saved-mistake-in-prep`, `survival/mated-as-black`

**END-2** · port
Survival's record counts the run for the whole game and every opening its
line went through: moves survived (best only goes up, recent form is the
median of the last 5, the chart keeps the last 16) and points, when any of
moments, missions and combo is on. A run you end yourself is only counted.
Source: `survival.recordSurvival`, `survival.recordEndedSurvival`, `survival.recentForm`, `survival.openingsAlong`; survival-end-run (10-31)
Cases: `survival.recordSurvival (runs)`, `survival.recentForm`, `survival.openingsAlong`, `const:RECENT_RUNS`, `const:HISTORY_RUNS`

**END-3** · port
When the run ends past its last answer, the openings only that last stretch
reached take the run's rated answers (LEARN-10), and the end screen's rating
card plays back every rating the run moved.
Source: `scoring.settleRun`
Cases: `scoring.applyResult (a run)`

## Grow this line

**END-4** · port
Only a clean finish (RUN-21) earns a way into Growth. It grows from where
the prep ran out, not from wherever the game went after.
Source: `SurvivalScreen.finish`, `growOffer.growOfferAt`; grow-from-autopilot (10-25)
Cases: `growOffer.growOfferAt`

**END-5** · port
A stub (an opening saved as its own moves, which asked nothing) offers to
grow the opening, from your own last move, with a plain button.
Source: `growOffer.growOfferAt`; onboarding-redesign (10-25)
Cases: `growOffer.growOfferAt`

**END-6** · port
An opening every line of which has been finished clean 3 times since it last
changed is offered whole, with a card that says "You finish every <opening>
line cleanly.", adding "Grow it with rarer replies." or "Grow it deeper." when
the offer had to look past Growth's settings to find something.
Source: `growOffer.growOfferAt`, `growOffer.readyToGrow`, `growOffer.lineFinishes`, `growOffer.growLaunch`; grow-offer-at-end-of-prep
Cases: `growOffer.growOfferAt`, `growOffer.readyToGrow`, `const:CLEAN_FINISHES`

**END-7** · port
Otherwise, a run that ended on a reply you have no answer to, or on your own
last move with the book still to reply, offers "Grow this line", right there,
past Growth's depth one move at a time. Past the book there is no offer.
Source: `growOffer.growOfferAt`, `growOffer.holeAtEnd`, `growOffer.endAtEnd`
Cases: `growOffer.growOfferAt`

**END-8** · port
The offer is about the opening the round started inside, or the selection;
a round from move one with nothing selected offers the family it ended in.
Source: `growOffer.offerOpening`
Cases: `growOffer.offerOpening`

**END-9** · port
Growth points back to practice once an opening owes its cap of lines short of
3 clean finishes: 3 while it has under 6 lines, 2 under 12, then 1.
Source: `growOffer.practiceOwed`, `growOffer.practiceCap`, `growOffer.atPracticeCap`, `growOffer.practiceText`; growth-return-nudge
Cases: `growOffer.practiceOwed`, `growOffer.practiceCap`, `growOffer.practiceText`

## The end screen

**END-10** · port
A blunder stays on the board, with the threat as a red arrow, until you tap
Continue; then the end screen shows. Every other ending shows it at once.
Source: `SurvivalScreen.finish`; blunder-threat-arrow (10-26)
Cases: `e2e:survival-runs`, `e2e:autopilot-first-runs`

**END-11** · port
In Autopilot the end screen has a Final position tab and an End of prep tab,
and opens on Final position. Its button to go on is Next round.
Source: `End.tsx`; grow-from-autopilot (10-25), end-of-round-screen
Cases: `e2e:autopilot-first-runs`

## Conflicts for the owner

None found so far in this area.
