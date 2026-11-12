# Play: what it is for

Check every change to Play against this note. Play was reshaped seven
times between September 13 and October 22, 2026, because it kept chasing
two goals at once: drilling your prep and being the fun game. This note
settles which goal wins. It was agreed on 2026-10-22, and widened on
2026-11-07 so that Play also grows your Playbook at a steady pace.

Play is the app's one game mode; Middlegame and Endgames are the only other
modes. What the code does, rule by rule, is in [rules](rules/README.md).

## Intent

**Play is the free game.** One tap, and you play real chess from your
openings until you blunder. Every prepared move tells you whether it was
right and how fast you played it. Play decides what you practice, so you
never configure anything, and it keeps your Playbook sharp in the
background. Now and then a run stops at a reply you have no answer to and
asks you for one, so your Playbook grows at a steady pace without
overwhelming you.

The core loop: Drill with Any Opening or one of your openings, and Freeform
when you want whole games from move one. Most runs still reach the end of
your prep, play book moves and go out of book. Growing is the exception,
not every run.

Every change should pass these tests:

- **One kind of round.** Every round is a run against an opponent. No round
  asks you to answer positions out of context.
- **Fun first, drilling underneath.** What you need to practice is handled
  by where the run starts and what the opponent steers into. Play never
  ends a run to send you to another mode. Adding moves at a hole happens
  inside the run, on its board, and the same game goes on after.
- **Instant, visible feedback.** On every prepared move you see whether it
  was right and how fast it was. Past your prep, a common move gets a quiet
  tick in the book's color, and any other move the engine's move score.
  When there's a strong move to find, the board glows green, and it pulses
  green or red once you've found or missed it.
- **Speed decides what you drill.** It never costs points or ends a run. It
  grades the position's card, and the cards decide which positions runs
  start at and steer toward. Speed and accuracy also decide when a line gets
  new moves: mastery is a weight, never a gate.
- **Need is counted in runs, not days.** Someone who plays thirty runs a day
  and someone who plays one a week both get repetition that fits how much
  they play.
- **No setup.** Play's settings are matters of taste, such as turning
  feedback on or off. They never change what you practice or how. Two
  exceptions: Moves per fill, which sets how many moves a fill adds and so
  how often new moves come, and the Freeform/Drill switch under Home's Play
  button.
- **It is the whole product.** If a player can't get somewhere without
  Middlegame or Endgames, Play has a gap.

## What it is not

- It is not a mode picker. Freeform and Drill are one kind of round that
  only starts differently.
- It is not a Playbook editor. It adds moves only at the one hole a run
  reaches. Other growing is done from Home's Recommendations or an
  opening's Grow.
- It is not where you choose an exact line, side, steer or clock.
- It never starts from the opening's named position just because it is
  named, and never asks which first move an opening wants: learning names is
  not a goal.

## Free and paid

Not decided. Nothing is paid until a paywall is built.
