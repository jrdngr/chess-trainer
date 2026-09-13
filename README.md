# Repertoire Trainer

A mobile-first chess opening trainer built around one idea: you are never
forced down a line. You pick a side and a region of the opening tree — the
whole book, one first move, a family like the King's Indian, or a single
variation — and every mode works inside it. A move keeps you alive if it is
prepared or it is theory. Autopilot chooses the next game for you, points are
credited to every opening a line goes through, and a Stats tab keeps the
record.

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

**Autopilot is the main loop.** A recommendation engine chooses a mode, an
opening inside the selection and a colour, one game after another, with no
trip back to Home in between and no end until you stop. Modes stay selectable by hand.

**Optimise for fun.** Run is the most fun, Drill less, Growth and Repair least.
The engine tilts toward fun without ignoring need. Every mode pays points, the
points climb a milestone ladder, and each opening keeps its own record.

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

Autopilot plays one game after another. A game is one Run, five Drill answers,
one Growth run, or five Repair items. When a Run ends, a bar over its reveal
shows what it earned and names the next game, and one tap starts it — the
reveal is worth reading. Every other game moves straight on to the next.
A session never ends on its own. Stop is the close button in the app bar, and
stopping opens Stats. Play is not in the rotation; a full game breaks the
rhythm and is one tap away by hand.

Under Autopilot a Run or Drill is always on a ten-second clock, with no hints
and no extended play.

### The recommendation engine

`src/model/recommend.ts` ranks every candidate of (mode, opening, colour)
inside the selection:

- **Need** is how loudly the work asks: cards due, holes in the prep, positions
  your games disagree with, prep no run has tested. Each saturates, so two
  hundred due cards are not ten times louder than twenty.
- **Staleness** is how long that opening has gone without that mode, measured
  against the other candidates rather than the clock. Candidates never played
  are all equally stale.
- **Star**: an opening that is starred, or sits inside one that is, is worth
  1.6×.
- **Fun**: Run 1.0, Drill 0.7, Repair 0.5, Growth 0.4.
- **Brake**: for every one of the last five games that was this mode, its
  weight is multiplied by 0.6. Counted over a window rather than consecutively,
  so two modes taking turns still let a third come round.

Score is need × staleness × star × fun × brake. Need is measured on
everything inside an opening, so a family asks at least as loudly as any of
its variations; the winner is then narrowed while a variation holds more than
half of its parent's work, so a game lands on the variation that wants it and
stays at the family when the need is spread thin. Only openings the player has
prep inside are candidates, besides the selection itself, and Run in the
selection always qualifies, so a brand new install gets a Run through the book.

## Modes

### Run
One secret line, played until the first mistake. Inside the region, a move
keeps you alive if it is in your repertoire or in the book. The opponent
replies in proportion to how often each move is played, confined to the
region; on the way in, confined to moves the book can still reach the opening
from. Past the end of the book your prep is the only referee, and past the end
of the prep the line is complete.

Where you have prepared lines through the region, one is drawn to steer the
opponent — weighted by how often you would actually meet it, and by how badly
you answer it when "target weak spots" is on. Where you have none, the
opponent walks you down the opening's own move order.

A theory move that your prep does not have pauses the run: add it and carry
on, carry on without adding it, or stop. Only a move nobody plays is a plain
loss. That makes four endings, coloured apart: green (finished, never left
prep), yellow (finished, having left it), red (a move nobody plays), purple
(ended out of prep).

Dying buys the reveal: the line named, the board a replay of the whole line
parked on the position that ended it, the mistake in red beside the prepared
move in green. Save line writes what you survived into your repertoire.

Options: clock (off, 10s, 30s a move), hints (the square a move starts from,
never where it lands), target weak spots, extended mode (past the prep, the
engine judges and a blunder ends the run).

### Drill
Positions inside the region, drawn from the schedule: due first, then new,
then extra practice. Right earns a grade of Guessed / Hard / Knew it / Easy;
wrong is graded `again` automatically and offers **Why?**, **Show line** and
**Explore**. "Follow the line" keeps going after a correct move. A session has
no length by hand; under Autopilot it is ten answers.

Scheduling is a small SM-2 variant in `src/model/srs.ts`. Answering early
never pushes a card out.

### Growth
The opponent walks your own prep toward the nearest reply you have no answer
to, and you choose one from the book. Up to three moves a run. Holes are only
counted inside the region, and on the way into it.

### Repair
The positions your imported games got wrong, compared against the repertoire:
off prep (you had a move and played another) and unprepared (you kept reaching
it with nothing). Slips made in the app count too. Scoped to the region.

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
games in the last thirty days — and the variations under it. Every row in the
opening picker opens its page too. History is kept for ever.

## Repertoire

One tree per colour. Openings are derived from the tree rather than stored:
an opening is the region beginning where the book starts naming the position.
Transpositions collapse to one card. Browse by playing moves; each move has a
sheet to prefer it, note it, reorder it, train the branch, or delete it. The
reference database sits under the move list.

A new install starts empty. Play writes openings from your games, Run offers
to keep the lines you survive, Growth fills what they leave out.

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
