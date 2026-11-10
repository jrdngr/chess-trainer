# Autopilot: what it is for

Check every change to Autopilot against this note. Autopilot was reshaped
seven times between September 13 and October 22, 2026, because it kept
chasing two goals at once: drilling your prep and being the fun game. This
note settles which goal wins. It was agreed on 2026-10-22, and widened on
2026-11-07 so that Autopilot also grows your Playbook at a steady pace.

The app calls Autopilot **Play**. The code and this note keep the name
Autopilot. Play is the app's one game mode; Middlegame and Endgames are the
only other modes.

## Intent

**Autopilot is the free game.** One tap, and you play real chess from your
openings until you blunder. Every prepared move tells you whether it was
right and how fast you played it. Autopilot decides what you practice, so you
never configure anything, and it keeps your Playbook sharp in the
background. Now and then a run stops at a reply you have no answer to and
asks you for one, so your Playbook grows at a steady pace without
overwhelming you.

The core loop: Drill with Any Opening or one of your openings, and Freeform when you
want whole games from move one. Most runs still reach the end of your
prep, play book moves and go out of book. Growing is the exception, not every
run.

Every change should pass these tests:

- **One kind of round.** Every round is a Survival run against an opponent.
  No round asks you to answer positions out of context.
- **Fun first, drilling underneath.** What you need to practice is handled by
  where the run starts and what the opponent steers into. Autopilot never
  ends a run to send you to another mode. Adding moves at a hole happens
  inside the run, on its board, and the same game goes on after.
- **Instant, visible feedback.** On every prepared move you see whether it
  was right and how fast it was. Past your prep, a common move gets a quiet
  tick in the book's color, with no time or word, and any other move the engine's
  move scores. When there's a strong move to find, the board glows green, and it
  pulses green or red once you've found or missed it.
- **Speed decides what you drill.** It never costs points or ends a run. It
  grades the position's card, and the cards decide which positions runs start
  at and steer toward. Speed and accuracy also decide when a line gets new
  moves: mastery is a weight, never a gate.
- **No setup.** Autopilot's settings are matters of taste, such as turning
  feedback on or off. They never change what you practice or how. Two
  exceptions: Moves per fill, which sets how many moves a fill adds and so
  how often new moves come, and the Freeform/Drill switch under Home's Play
  button (see How a run starts).
- **It is the whole product.** If a player can't get somewhere without
  Middlegame or Endgames, Autopilot has a gap.

## What it is not

- It is not a mode picker. Freeform and Drill are one kind of round that
  only starts differently.
- It is not a Playbook editor. It adds moves only at the one hole a run
  reaches (see Growing inside a run). Other growing is done from Home's
  Recommendations or an opening's Grow.
- It is not where you choose an exact line, side, steer or clock.

## How a run starts

| Start | What happens | When |
| --- | --- | --- |
| Position start | The moves up to the opening's own position are played for you | Default, when you have moves of your own past that position |
| Inside start | The moves to one position deeper inside the opening are played for you: the one most overdue, or, with nothing due while your prep keeps missing, the one you answer worst | When it needs it more than a cold start does, never two runs in a row |
| Cold start | Nothing is played for you. The run starts from move one and the opponent steers toward the opening | When the way in has gone unplayed long enough, never two runs in a row, and at least every 3rd run. Also whenever your prep ends at the opening's own position, so a run never plays your whole prep for you |

Under Home's Play button, a switch picks how runs start, for any selection:

- **Drill** (the default): the starts in the table above.
- **Freeform**: every run is a cold start. Nothing is played for you, and the
  opponent steers toward what needs work.

The first run of an opening added from a menu is always a position start,
whatever is owed, so you see how the opening is reached before you are asked
to reach it yourself. An opening grown by playing moves needs no such start.
A run that starts inside its line opens on that position; nothing is played
out by itself. Until your first move, a Replay moves button under the board
puts the board back to move one and plays the moves up to the position, then
hands it back. Inside starts go to any position you have a card for.

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

## What the next run is

The recommendation engine picks it: one stateless, deterministic set of
functions, one per question, computed from the Playbook, the in-app game
history (for staleness and how often things come up) and the book. The same
data gives the same run.

Black's basics come first. With Black or Random picked and no Black answer
to 1.e4 or 1.d4, the next run is Black from move one: the opponent opens
with that move and you add your answer before the game goes on. It waits
until the last game added nothing, so two fills never come back to back:
after the first game, the next one plays the White opening it grew.

When a new move is due (see below), the next run steers toward the gap in the
selection with the highest p × m² × g, among the gaps past at least one move of
yours. A White first move you have no answer to is left to Home's
Recommendations: a run never steers there or grows there: the opponent follows that gap's line
to its reply, so new moves land on strong lines at a steady pace instead of
whenever chance allows.

## Growing inside a run

A gap is a common opponent reply in your Playbook that you have no answer
to: at least 5% of strong players' games at that position, inside the
opening the book names, and met in at least 2% of your games once deeper
moves are discounted. A run reaches at most one hole, the first reply you
have no answer to. At that hole the engine answers one question: does this
line need a new move now? Yes when

p × m² × g ≥ 1

- p (pace) is the Autopilot runs since anything was added to the Playbook,
  from any source, over Moves per fill (default 3), so a well known line gets
  about one new move per run.
- m (mastery, 0 to 1) is how well you know your moves along the line, from
  move one to the hole. Right, fast answers count most; moves never asked
  count as weak.
- g (gap, 0 to 1) is the hole's importance next to the top gap in the
  selection.

On a yes, the run's board turns into New move: the book's answers, Undo and
Done. Each pick is saved as it is made, the book's most played reply comes
back, and it stops after Moves per fill of your moves, at the end of the
named opening, or when no reply is common enough. Done stops it at any time,
even with nothing added. The same game then goes on from there; the new
moves are not graded this run, and later runs drill them.

On a no, a Grow here button shows while it is your move at the hole, the
only growth button in a run. The end screen has no growth button.

## Past your prep: common moves

Your Playbook ends where the book does, and the engine's gaps never go past
it (manual Growth can, with Past the book on), so most lines are short. A run doesn't get shorter for it. Once a clean prep
runs out, the run stays in the book phase for as long as the position is in
the book:

- A move counts as a book move when at least 5% of strong players' games play
  it there and the engine doesn't call it a mistake. It gets only a quiet
  tick in the book's color: no time, no word, and nothing on the status line,
  which says Prep complete.
- Book moves count for the run's points and keep the combo going. They never
  move a rating or a card: those measure what you chose to learn.
- A move that isn't a book move costs nothing. The engine judges it as usual,
  and the book phase is over. It's also over where the book has nothing more
  to say.
- The prep bar counts only your line: common moves past it aren't added.
- The end screen and Analysis mark common moves with a small book.

Moments and missions start as soon as your prep runs out, book phase
included. After the book the rest of the
middlegame extras take over: the combo, plan cards and lenses.

Once little material is left (queens 4, rooks 2, minor pieces 1, 8 or less
in all), the header says **Endgame** and a blunder means giving away the
result: a win slipping to a draw, or a draw to a loss. A slower win costs
points, never the run, and a missed mate gets a note instead of ending it.
The lenses switch to their endgame forms. Autopilot never starts a round in
an endgame: endgames are drilled in Endgame mode.

## The tutorial

A new profile's first five runs are the tutorial's games, on the three
openings it starts with (one for White, Black's answers to 1.e4 and 1.d4).
They bend the rules above on purpose: the first games force your moves and
the opponent's, two of them grow your line with a fixed number of moves, and
three ask you to end the run with the X so ending early is learned as free.
Everything else (prep grading, common moves, scores, blunders) works as in
any run. `Sources/Model/Tutorial.swift` holds each game's setup.

## Ending a round

A small, quiet End round button is under the board from the first move of
every run. Ending a round still gets the normal end screen, with Analyze, so
you can drill just your openings when you want to. It is
quiet on purpose: playing on past your prep is the game, and it is what makes
you care which moves you grow.

The end screen opens on the final position, with "End of prep" and "Final
position" to switch between where your prep ran out and where the run
finished. Its main button is Back Home: the next run waits on Home's Play
button, named by its opening.

## How a run is shown

Autopilot never names a mode. A run is called by its opening, with the side as
a small square. The round intro deals the run's card from a deck: the start
position face up, the opening's full name above it ("Sicilian: Najdorf"), a
row of segments below; the board's orientation shows the side. The segments show how far into your prep the
run starts: one segment for each of your own moves, lit up to where you take
over. After a beat the card grows into the board and the run begins; a tap
goes straight to the board. Home's button, the round intro and the end screen
all show the segments. During the run, the app bar shows the
opening, the same segments counting up as you play, and the rating the run has
gained so far. In Freeform, where every run starts from move one, Home's
button, the round intro and the app bar show no segments. Home's button still
names the opening the opponent steers toward.

## Free and paid

Not decided. Nothing is paid until a paywall is built.
