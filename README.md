# Repertoire Trainer

A mobile-first chess opening trainer built around one idea: you are never
forced down a line. You pick a side and a region of the opening tree — the
whole book, one first move, a family like the King's Indian, or a single
variation — and every mode works inside it. A move keeps you alive if it is
prepared or it is theory. Autopilot plays Run after Run on settings it chooses
for you, points are credited to every opening a line goes through, and a Stats
tab keeps the record.

This is a **UX prototype**, not a product. It exists to answer questions about
what the eventual native app should be.

## Goals and direction

**Flexibility across lines is the point.** Other trainers make you pick a line
and then play its moves. This one lets you play your repertoire, or any move
within the opening that leads to a valid line. That minimises the choices you
have to make up front and makes it feel like a game rather than training.
Everything below leans into it.

**One selection, everywhere.** The side and the opening are chosen once, at the
top of Home and every setup screen, and every mode honours them. Setup screens
only hold what is specific to that mode.

**Autopilot is the main loop, and it is all Run.** Run can do everything the
other modes do: it can repeat what needs repeating by steering the opponent
toward it, and it can grow the repertoire by offering the book where the prep
ends. So a recommendation engine chooses an opening inside the selection, a
colour, and the Run's settings, one round after another, with no trip back to
Home in between and no end until you stop. The settings are the engine's
business and nothing on screen names them. The four modes stay selectable by
hand, each with its own setup, for training on your own terms.

**Optimise for fun.** A Run that just runs is the most fun; one that stops to
offer the book is a little less. The engine tilts toward fun without ignoring
need. Every mode pays points, the points climb a milestone ladder, and each
opening keeps its own record.

## Run it

```bash
npm install
npm run dev          # http://localhost:5173, also served on your LAN IP
```

`npm run dev` binds to `0.0.0.0`, so a phone on the same Wi-Fi can open
`http://<your-laptop-ip>:5173`. On iOS, Share → Add to Home Screen gives a
full-screen, chrome-free app.

```bash
npm test             # chess rules, tree, SRS, PGN, analysis, runs, regions, scoring, the engine
npm run typecheck
npm run build        # production build into dist/
npm run artifact     # repackage dist/ for publishing as a Claude Artifact
```

## The selection

Two controls sit at the top of Home and every setup screen: a colour square
(white, black, or a diagonally split square for random) and the opening. Live
games show the selection as the app bar subtitle and do not let it change.

The opening is picked from a tree. The root is *any opening*. Under it sit the
first moves, ordered by how often they are played; under each first move the
families; under each family its variations, as deep as the book's names go.
Most branches are three deep. The Najdorf branch is five. Any level can be
selected, and any level can be starred: starred openings lead every level of
the picker in their own section, and a star lifts an opening in the engine.

Nesting follows the moves first and the book's family names second, so the
Fianchetto King's Indian files under the King's Indian even though its move
order never passes through the position the book names.

Selecting a node means *anything that goes through here*. That is judged on
positions rather than move orders, so a transposition counts. Before the line
reaches the position that names the opening it is *on the way*, and only moves
the book can still reach the opening from are allowed; once it has reached it,
anything inside is fair.

## Autopilot

Autopilot plays one round after another, and every round is a Run. When it
ends, a bar over its reveal shows what it earned and offers the next round,
and one tap starts it — the reveal is worth reading. A session never ends on
its own. Stop is the close button in the app bar, and stopping opens Stats.

Under Autopilot a Run is always on a ten-second clock, with no hints and no
extended play. What changes from round to round is the opening, the colour,
where the round starts, and two of Run's own settings: what the opponent
steers toward, and how many moves the run may add. The player is told none
of it; the bar says "Next Round" and nothing else.

Most rounds start from move one and follow the player. The opening the
engine chose is only what the opponent steers toward: play something else
and the round comes with you, re-steering from wherever you take it (see
Run). A theory move your prep does not have is simply your move under
Autopilot — no pause, though the reveal still says the run left your prep.
Now and then a round is *steered* instead: it starts inside a family or a
variation, with the way in already on the board, dimmed, and your first
decision is the first move inside. That is how the engine drills one
variation or grows one opening, and it is kept rare. Home's Autopilot button
says which the first round would be: "Black, from move one", or the opening
it would start inside.

### The recommendation engine

`src/model/recommend.ts` ranks every candidate of (focus, opening, colour)
inside the selection. A focus is a preset of Run settings:

- **Test**: lines drawn by how often you would meet them, nothing added.
  Whether the prep holds up when nothing says what it is.
- **Review**: lines drawn toward the positions you answer badly, have let
  lapse, are due on, or got wrong in your own games; nothing added.
- **Grow**: the opponent walks you to a reply you have no answer to and the
  run offers the book, one to eight moves depending on how much line there is
  left to build.

Before any of that, the **foundation**: with no opening selected, a repertoire
is first given something to play as White, then an answer as Black to 1.e4,
then to 1.d4 — in that order, ahead of every other candidate, because until
all three are in it is not a repertoire that can be played. A side chosen on
its own gets its own part (an answer to 1.e4 and 1.d4 for Black; a first line
for White); an opening chosen is what the player asked for and is what they
get.

Likewise an opening chosen with nothing of yours in it: the first round there
builds a line, by the opening's own move order, before the ranking has a say —
choosing the Najdorf with no Najdorf prepared is a request for a Najdorf. The
moves it takes to get there past your prep are not charged against the round's
budget; only the opening itself is.

Each candidate is scored:

- **Need** is how loudly the work asks: cards due (a position your games got
  wrong counts as due), holes in the prep (weighed up by the games you reached
  them with nothing), prep no run has tested. Each saturates, so two hundred
  due cards are not ten times louder than twenty.
- **Readiness** gates Grow. Holes in an opening only ask at full voice once
  the prep around them is held: a position counts as held when its card has
  graduated, is not due, and has a review interval of a week or more. Half
  held is a quarter of the voice; an opening still being learned asks at a
  tenth at most, so it is grown now and then rather than never. An opening
  with no prep yet is ready, which is how a new repertoire gets its first
  lines.
- **Thinness** undoes that gate for an opening that barely exists, because the
  readiness rule is about prep being learned and there is none here to learn.
  It is not how much prep an opening holds — a King's Indian eighteen plies
  deep down one pawn storm is a great deal of prep and the narrowest
  repertoire there is — but how much of what the opponent would actually play
  you answer, at each position where they have a real choice, weighted toward
  the early ones. Readiness and thinness decide *whether* to grow an opening;
  how much a round adds is decided by the line it walks to, not here.
- **Staleness** is how long that opening has gone without a round, measured
  against the other candidates rather than the clock. Candidates never played
  are all equally stale.
- **Freshness** (`src/model/freshness.ts`) is what the last few rounds were
  about. Every Run stamps the positions of the line it was drawn on with its
  round number, and a line is then read in two parts: its tail — the moves
  past where it last parts from another line, what makes it *this* line — and
  its head, what makes it this opening. A Test asks only as loudly as the
  stalest line in the opening has been left (fully stale after three rounds),
  so the line just built is run once and the opening then grows rather than
  running it again; the draw prefers the line left longest, and never draws
  the line the last round was drawn on while there is another. Grow's draw
  reads the same stamps: a hole at the tip of the line just run is that round
  again with a move on the end, and loses to a junction earlier in it. No
  schedule: a one-line repertoire runs it, finds it fresh, and grows; forty
  lines cycle a rotating few.
- **Depth**: how far below the selection the opening sits, at 0.6 a level —
  the selection 1, a first move 0.6, a family 0.36, a variation 0.22. Most
  rounds are spent at the selection, from move one; a family left alone
  while the selection was just played still comes round, a fresh one does
  not.
- **Star**: an opening that is starred, or sits inside one that is, counts
  one level shallower.
- **Fun**: Test 1.0, Review 1.0, Grow 0.7.
- **Brake**: for every one of the session's last five rounds that was this
  focus, its weight is multiplied by 0.6. Counted over a window rather than
  consecutively, so two focuses taking turns still let the third come round.
  The session remembers its own rounds; nothing is saved.

Score is need × staleness × depth × fun × brake. Need is measured on
everything inside an opening, so a family asks at least as loudly as any of
its variations. A Review or Grow that wins is then narrowed while a variation
holds most of its parent's work — half to step to a first move, two thirds
to a family, three quarters to a variation, a star taking a level off — so a
round lands on the variation that wants it and stays at the family when the
need is spread thin. A Test is never narrowed and is only ever the selection:
what it measures is whether the prep holds up when nothing says what it is.
Only openings the player has prep inside are candidates, besides the
selection itself. A side with nothing prepared is offered one thing, a Grow
round in the selection, so a brand new install gets its first line from the
book.

A round on a family or deeper starts inside it; one on the selection or a
first move starts from move one. A repertoire of one line per opening
concentrates all of its work at every level, and every Review and Grow would
start inside the deepest variation there is — so the session spaces them:
after a round steered into an opening below the selection, the next three
are drawn from the openings a round can start from move one. Steered rounds
are the exception, and stay one.

## Modes

### Run
One secret line, played until the first mistake. Inside the region, a move
keeps you alive if it is in your repertoire or in the book. The opponent
replies in proportion to how often each move is played, confined to the
region; on the way in, confined to moves the book can still reach the opening
from. Past the end of the book your prep is the only referee, and past the end
of the prep the line is complete.

Where you have prepared lines through the region, one is drawn to steer the
opponent. "Steer toward" decides how: *popular* draws by how often you would
actually meet each line; *weak spots* tilts hard toward positions you answer
badly, have let lapse, or got wrong in your own games; *gaps* walks you to a
reply you have no answer to. Where you have no lines, the opponent walks you
down the opening's own move order.

The drawn line is not a fence. Any move that stays inside the region is
accepted, and when yours leaves the line a new one is drawn from where you
now are, by the same steer — one of your lines through this position, your
weakest, or the walk to the nearest hole from here — so the opponent keeps
steering rather than wandering. A line reached by a transposition counts.
Only where nothing of yours passes through the position does the opponent
fall back to the book, by popularity.

A run can also start *inside* an opening: the way in is played onto the
board first, shown dimmed, earns nothing and reviews no cards, and is kept
with the line when the run is written into the repertoire. Autopilot uses
this for its steered rounds; a Run started by hand always begins at move
one.

Every move of yours on a position your prep has an answer to is a review of
that position's card, graded by how long it took, so Run and Drill share one
schedule and a run does not ask again what it has just shown you know.

A theory move that your prep does not have pauses the run: add it and carry
on, carry on without adding it, or stop. Only a move nobody plays is a plain
loss. That makes four endings, coloured apart: green (finished, never left
prep), yellow (finished, having left it), red (a move nobody plays), purple
(ended out of prep).

Where the prep ends — your move, nothing prepared, the book still going — the
run is complete, once it has asked you at least eight moves of your own
(`MIN_DECISIONS`). Before that it carries on into the book: the book judges
every move, the opponent plays from the book, and what you survive is
written into the repertoire, so a stub of an opening — the five plies
onboarding wrote for a starred Ruy López — grows by being played rather
than ending the run after three moves. Carrying on is not leaving the prep,
so a finish stays green; the reveal says how many moves the book judged.

With "new moves" left the run pauses at the edge instead and offers the
book's replies, with how often each is played; the one you choose is written
into the repertoire and the run carries on, up to the run's budget of new
moves. A chosen move earns nothing: the score is moves you found.

Dying buys the reveal: the line named, the board a replay of the whole line
parked on the position that ended it, the mistake in red beside the prepared
move in green. Whatever you survived is written into your repertoire, every
run: a line you have played through is a line you play.

Options: steer toward (popular, weak spots, gaps), new moves (0 to 8), clock
(off, 10s, 30s a move), hints (the square a move starts from, never where it
lands), extended mode (past the prep, the engine judges and a blunder ends the
run). Autopilot sets the first two for itself.

A gaps run draws the hole it walks to on how often you would actually meet it:
the reply's share of its position, times the share of games that reach the
position at all — every opponent choice on the way, multiplied together. Your
own moves cost nothing, because you are the one making them. That single
number orders the work without any rule about depth: an unanswered 1.e4 is met
in four games in ten, a sideline at the same position in one in a hundred, the
end of a line you reach one game in twenty in less than that.

With an opening selected, the hole is one inside it while there is any: a hole
on the way in — 1.c4, met in every game and on its way to the Sämisch only by
transposition — would otherwise take every round from the opening chosen. The
way in is walked to once nothing inside is left to answer.

It is drawn rather than taken in order, so the rounds are not the same round
twice — but drawn only from the holes worth at least an eighth of the best one
(`DRAW_WINDOW`). Proportional drawing is fair and still wrong: it spends one
round in a hundred on a move you will not meet while the move you meet in four
games in ten goes unanswered. Answering the top hole takes it out of the
reckoning, the best of what is left is worth less, and the window comes down to
the next tier — so the common replies are covered first and the obscure ones
arrive when there is nothing commoner left to do.

How many moves a round adds is fitted to the line rather than to the
repertoire (`movesToFit`): each answer carries a line two plies on, so the
budget is the plies left to the horizon, halved. Nothing prepared against 1.e4
gets eight answers and a real position in one round; a line already fourteen
plies deep gets the next move or two and no more. Never more than the run was
allowed to begin with, and never less than one.

### Drill
Positions inside the region, drawn from the schedule: due first, then new,
then extra practice. Right earns a grade of Guessed / Hard / Knew it / Easy;
wrong is graded `again` automatically and offers **Why?**, **Show line** and
**Explore**. "Follow the line" keeps going after a correct move. A session has
no length: it ends when you end it.

Scheduling is a small SM-2 variant in `src/model/srs.ts`. Answering early
never pushes a card out.

### Growth
The opponent walks your own prep toward the nearest reply you have no answer
to, and you choose one from the book. Up to three moves a run — this mode's
own cap, not the Run's budget. Holes are only
counted inside the region, and on the way into it. This is the picker a Run
opens at the edge of the prep, as a mode of its own.

### Repair
The positions your imported games got wrong, compared against the repertoire:
off prep (you had a move and played another) and unprepared (you kept reaching
it with nothing). Slips made in the app count too. Scoped to the region. Under
Autopilot the same evidence steers Run instead: a slip makes its position a
weak spot, and a position reached with nothing makes its hole ask louder.

### Play
A game against the engine at a chosen strength. While the game is still on the
selected opening's move order the engine plays that move order, so a game in
the Najdorf is a Najdorf; past it the engine plays for itself. The opening can
be saved into the repertoire when the game ends.

## Score

Points are reward, not assessment. Nothing is ever subtracted. All the numbers
live in `POINTS` in `src/model/scoring.ts`.

| Mode | Per action | Bonuses |
|---|---|---|
| Run | 1 per correct move | +5 finishing the line, +3 more for green; speed; combo |
| Drill | 1 per correct answer | +1 on a card that had lapsed; speed; combo |
| Growth | 5 per move added | |
| Repair | 4 per position relearned, 2 per move given | |

**Speed.** On a clock, a correct move earns +2 in the first half of the budget
and +1 in the second. Running out costs nothing but the bonus: the clock parks
at zero and the move is still yours to make. The clock and the bonus it is
still worth sit together in the app bar, and shake when they reach nothing.

**Combo.** From the third correct move in a row in one game, +1 more each.

**Where points go.** Every event credits the deepest opening its line goes
through, every opening above it, and the global total. A Sämisch move scores
for the Sämisch, the King's Indian, and 1.d4.

**Milestones.** Infrared, red, orange, yellow, green, blue, indigo, violet,
ultraviolet. The ladder is geometric (100 points, then ×1.6 each) and never
ends: past ultraviolet the label counts on, "Ultraviolet II" and so on. A
first move's ladder is four times a variation's, a family's twice, so a colour
means the same amount of work at every level. A bar slides in at the top
whenever points land, fills toward the next milestone in that milestone's
colour, and celebrates when one is crossed. Tapping it opens Stats.

## Stats

The Stats tab leads with the total, the daily streak, accuracy and the
milestone ladder, then score as it climbed and a seven-day accuracy average
over a chosen window, points by mode, and every opening with a score. Each
opening has a page of the same shape, on its own ladder, plus its
*favouriteness* — its rank among the siblings you have actually played, by
rounds in the last thirty days — and the variations under it. A round is one
Run, one Drill session, one Growth run or one Repair sitting: none of them is
a game of chess, so none is called one. Every row in the
opening picker opens its page too. History is kept for ever.

## Repertoire

One tree per colour. Openings are derived from the tree rather than stored:
an opening is the region beginning where the book starts naming the position.
Transpositions collapse to one card. Browse by playing moves; each move has a
sheet to prefer it, note it, reorder it, train the branch, or delete it. The
reference database sits under the move list.

A new install starts empty. Play writes openings from your games, Run keeps
the lines you survive and, with new moves allowed, the ones you choose;
Growth fills what they leave out.

## Analysis

Board, engine lines, eval bar, PGN in and out, and the reference explorer
underneath: move frequencies, results, opening names, a handful of master
games, and the named book lines the app knows from the current position, each
with a summary and ideas and one tap to add.

## Import your games

**Repertoire → Import** pulls recent games from Lichess or Chess.com, or a
pasted PGN, and feeds Repair. A published Claude Artifact runs under a CSP
that blocks cross-origin requests, so the live fetch fails there; pasting a
PGN and a bundled synthetic sample archive both work anyway.

## Data

State lives in IndexedDB (with a localStorage fallback) and, when the page runs
as a published Artifact, in the `db` runtime capability against your Claude
account — inside the artifact sandbox that is the only thing that persists.
Startup reads the account copy before deciding anything. The document is
gzipped and base64-encoded and capped at 256 KiB by the platform; the app says
so in Settings when it overflows.

Saved state carries a schema version. Version 0 is the fresh start: every
earlier save, settings included, is discarded rather than migrated.

The reference database is a small curated sample, authored as weighted paths
in `src/model/seed/openingPaths.ts` and folded into a tree at runtime. Every
seeded line is checked for legality by the tests.

## Design

Dark, borderless surfaces on a near-black ground, one indigo accent, white
primary buttons, iOS-style large titles and grouped lists. Tokens live at the
top of `src/styles.css`. Charts are inline SVG: one series, one hue, a
two-pixel line, hairline grid.

## Layout

```
src/
  chess/       rules, position keys, PGN parsing with variations
  model/       opening tree and regions, selection, run rules, SRS, session
               building, scoring and milestones, stats series, the
               recommendation engine, growth, repair, reference index, seed data
  engine/      Stockfish worker + heuristic fallback behind one interface
  store/       zustand store, IndexedDB persistence, cloud sync, the engine's input
  components/  board, pieces, explorer, the selection bar and pickers, the
               score bar, the move clock, charts, sheets, icons, shared controls
  screens/     Home, Stats, Repertoire, Analysis, Import, Settings, and one
               folder per mode: autopilot, openingRun, drill, growth, repair, play
```
