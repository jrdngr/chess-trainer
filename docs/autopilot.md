# Autopilot: what it is for

Check every change to Autopilot against this note. Autopilot was reshaped
seven times between September 13 and October 22, 2026, because it kept
chasing two goals at once: drilling your prep and being the fun game. This
note settles which goal wins. It was agreed on 2026-10-22.

## Intent

**Autopilot is the free game.** One tap, and you play real chess from your
openings until you blunder. Every prepared move tells you whether it was
right and how fast you played it. Autopilot decides what you practice, so you
never configure anything, and it keeps your Playbook sharp in the
background.

Every change should pass these tests:

- **One kind of round.** Every round is a Survival run against an opponent.
  No round asks you to answer positions out of context or to build lines.
- **Fun first, drilling underneath.** What you need to practice is handled by
  where the run starts and what the opponent steers into. Autopilot never
  switches to a different mode to do it.
- **Instant, visible feedback.** On every prepared move you see whether it
  was right and how fast it was. Past your prep, a book move gets the same
  tick and time in the book's color, and after the book you see the engine's
  move scores and the board glow.
- **Speed decides what you drill.** It never costs points or ends a run. It
  grades the position's card, and the cards decide which positions runs start
  at and steer toward.
- **No setup.** Autopilot's settings are matters of taste, such as turning
  feedback on or off. They never change what you practice or how.
- **It is the whole product for a free user.** If a free user can't get
  somewhere without a paid mode, Autopilot has a gap.

## What it is not

- It is not a mode picker. The paid modes are deeper versions of its parts
  that you configure yourself.
- It is not a Playbook editor. Its only way to add moves is the end
  screen's Grow this line, one button that looks the same wherever it shows,
  which grows the line where your prep ran out. That plays one batch of
  Growth and then goes on to the next run.
- It is not where you choose an exact line, side, steer or clock. Standalone
  Survival does that.

## How a run starts

| Start | What happens | When |
| --- | --- | --- |
| Position start | The moves up to the opening's own position are played for you | Default |
| Inside start | The moves to one position deeper inside the opening are played for you: the one most overdue, or, with nothing due while your prep keeps missing, the one you answer worst | When it needs it more than a cold start does, never two runs in a row |
| Cold start | Nothing is played for you. The run starts from move one and the opponent steers toward the opening | When the way in has gone unplayed long enough, never two runs in a row, and at least every 3rd run |

The first run of any opening is always a position start, whatever is owed,
so you see how the opening is reached before you are asked to reach it
yourself. Inside starts only go to positions a run has already asked you.

Need is counted in runs, not days. Someone who plays thirty runs a day and
someone who plays one a week both get repetition that fits how much they
play:

- A position's need grows with every run that didn't ask it, and resets when
  a run does. A position still being learned comes back every other run; a
  known one after its interval in runs, three runs for each day of it.
- The way in is needed when its stalest move has gone 6 runs without you
  playing it yourself.
- Where runs started is saved, so the every-3rd-run cold start counts across
  sessions.

## Past your prep: the book phase

Your Playbook ends where the book does, and Growth never adds a move past it,
so most lines are short. A run doesn't get shorter for it. Once a clean prep
runs out, the run stays in the book phase for as long as the position is in
the book:

- A move counts as a book move when at least 5% of strong players' games play
  it there and the engine doesn't call it a mistake. It gets a tick, "Book"
  and your time, in the book's color.
- Book moves count for the run's points and keep the combo going. They never
  move a rating or a card: those measure what you chose to learn.
- A move that isn't a book move costs nothing. The engine judges it as usual,
  and the book phase is over. It's also over where the book has nothing more
  to say.
- The prep segments keep counting through the book phase, in the book's
  color, so a short opening still fills out the bar.

After the book comes **Out of book**, and the middlegame extras take over:
moments, missions, the combo, plan cards and lenses.

## Ending a round

A small, quiet End round button is under the board from the first move of
every run. Ending a round still gets the normal end screen, with Analyze and
Grow this line, so you can drill just your openings when you want to. It is
quiet on purpose: playing on past your prep is the game, and it is what makes
you care which moves you grow.

The end screen opens on the final position, with "End of prep" and "Final
position" to switch between where your prep ran out and where the run
finished.

## How a run is shown

Autopilot never names a mode. A run is called by its opening, with the side as
a small square, and the opening's position faded in behind the name. A row of
segments along the bottom edge shows how far into your prep the run starts:
one segment a ply, lit up to where you take over. Home's button, the round
intro and the end screen all use this. During the run, the app bar shows the
opening, the same segments counting up as you play, and the rating the run has
gained so far.

## Free and paid

The paywall exists only in the native app. The web prototype has none.

| Free | Paid |
| --- | --- |
| Autopilot, Play, Analysis, the Playbook tab with editing and Tidy, ratings, Home, Stats, Milestones | Survival, Drill (positions and lines), full Growth, game import |

The native app builds Autopilot before any of the paid modes. Standalone
Survival and the other paid modes get improved after that.
