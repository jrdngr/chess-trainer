# Learning: cards and ratings

How the app schedules what you practice and rates how well you know each
opening. Cards are `src/model/srs.ts`; ratings are `src/model/scoring.ts`.
Need counted in runs, which reads the cards, is in
[autopilot.md](autopilot.md).

## Cards

**LEARN-1** · port
Every position your prep answers is a card, keyed by the repertoire and the
position (so a transposition is the same card). Every line of your prep is a
line card, keyed by its tip. A card starts new, with ease 2.5.
Source: `srs.createCard`, `srs.createLineCard`, `session.cardId`, `srs.lineCardId`
Cases: `srs.createCard`, `srs.createLineCard`, `const:DEFAULT_SRS`

**LEARN-2** · port
A review is SM-2 with no fuzz. Learning steps are 1 and 10 minutes; Good on
the last step graduates at 1 day, Easy at 4. Hard stays on its step. Again
goes back to the first step, and from review it is a lapse that halves the
interval and relearns at 10 minutes. Ease moves −0.2 on Again, −0.15 on
Hard, +0.15 on Easy, never under 1.3. In review, Hard is ×1.2, Good ×ease,
Easy ×ease×1.3, capped at 365 days.
Source: `srs.review`, `srs.DEFAULT_SRS`
Cases: `srs.review (one grade)`, `srs.review (schedule)`, `const:DEFAULT_SRS`

**LEARN-3** · port
A card reviewed right before it is due keeps its date: practicing early is not
evidence the interval was too short. Getting it wrong early still counts.
Source: `srs.review`
Cases: `srs.review (schedule)`

**LEARN-4** · port
A correct answer is graded by how long it took: under 3 seconds Easy, under 8
Good, otherwise Hard. The clock never grades an answer Again; only a miss, or
you, does.
Source: `srs.gradeForTime`; cards-judged-by-answer (10-07)
Cases: `srs.gradeForTime`

**LEARN-5** · port
A whole line is graded Again after any miss, otherwise by the average time of
your correct moves on the same scale.
Source: `srs.gradeForLine`; line-drill-grades (10-03)
Cases: `srs.gradeForLine`

**LEARN-6** · port
A card is due when its date has come. Waits are written as minutes, hours,
days, months or years (`srs.describeDelay`).
Source: `srs.isDue`, `srs.describeDelay`
Cases: `srs.isDue`, `srs.describeDelay`

## Ratings

**LEARN-7** · port
Each opening has a rating, starting at 0 and never below it. One result moves
it by 20 × (1 if right, 0 if wrong − the accuracy the rating expects), where
the expected accuracy is 1 / (1 + 10^(−rating / 450)). It is kept to two
decimals and shown rounded.
Source: `scoring.ratingAfter`, `scoring.expectedAccuracy`, `scoring.RATING`; rating-per-opening (09-21)
Cases: `scoring.ratingAfter`, `scoring.ratingAfter (walked)`, `scoring.expectedAccuracy`, `const:RATING`

**LEARN-8** · port
The tiers are Learning 100, Familiar 250, Solid 400, Strong 550, Fluent 700
and Mastered 850. Below the first, an opening reads New until it has been
rated at all, and Shaky once it has.
Source: `scoring.rankOf`, `scoring.TIERS`
Cases: `scoring.rankOf`, `const:TIERS`, `const:UNRATED`, `const:NEW_LABEL`

**LEARN-9** · port
Only Survival and Autopilot rate, and only answers at prepared positions. A
result counts for the deepest opening the book names along its line and
every opening above it, whether or not you starred it.
Source: `scoring.applyResult`, `scoring.creditedNodes`, `scoring.ratedNodes`; ratings-for-all-openings (10-05)
Cases: `scoring.creditedNodes`, `scoring.applyResult (a run)`

**LEARN-10** · port
An opening a run reaches for the first time takes every earlier rated answer
of that run first, in order, so the moves leading into a Najdorf count once
the run becomes one. When a run ends past its last answer, the openings only
that last stretch reached take the run's answers too.
Source: `scoring.applyResult`, `scoring.settleRun`, `scoring.rateRun`
Cases: `scoring.applyResult (a run)`

**LEARN-11** · port
An answer past where the line left the book rates the opening's Extensions
rating rather than its main one. A move saved as a mistake is never rated.
Source: `scoring.tallyRating`, `scoring.rateRun`; extensions-design (10-24)
Cases: `scoring.applyResult (a run)`

**LEARN-12** · port
Each move of a rating says whether it crossed a tier up or down, for the end
screen's promotion and demotion.
Source: `scoring.rateRun`
Cases: `scoring.applyResult (a run)`

## Conflicts for the owner

None found so far in this area.
