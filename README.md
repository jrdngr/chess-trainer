# Repertoire Trainer

A mobile-first chess opening trainer built around one idea: you are never
forced down a line. You pick a side and a region of the opening tree — the
whole book, one first move, a family like the King's Indian, or a single
variation — and every mode works inside it. Inside your prep a move keeps you
alive if it is prepared or it is theory; outside it the engine judges, and
only a blunder ends the game. Autopilot plays Run after Run on what you have,
the repertoire grows only when you say so, points are credited to every
opening a line goes through, and a Stats tab keeps the record.

This is a **UX prototype**, not a product. It exists to answer questions about
what the eventual native app should be.

**[Play it here.](https://claude.ai/code/artifact/8909c26a-7c93-47bc-9547-a426307eecd2)**
The live page is a published Claude Artifact, republished from `dist-artifact/`
whenever the app changes.

## Goals and direction

**Flexibility across lines is the point.** Other trainers make you pick a line
and then play its moves. This one lets you play your repertoire, or any move
within the opening that leads to a valid line. That minimises the choices you
have to make up front and makes it feel like a game rather than training.
Everything below leans into it.

**One selection, everywhere.** The side and the opening are chosen once, at the
top of Home and every setup screen, and every mode honours them. Setup screens
only hold what is specific to that mode.

**Autopilot is the main loop, and it is all Run.** Run can repeat what needs
repeating by steering the opponent toward it, so a recommendation engine
chooses an opening inside the selection, a colour, and what the opponent
steers toward, one round after another, with no trip back to Home in between
and no end until you stop. The settings are the engine's business and
nothing on screen names them. The four modes stay selectable by hand, each
with its own setup, for training on your own terms.

**Autopilot drills; it never builds.** Nothing is written into the
repertoire by playing. Growth is where lines are built, a Run offers the
line it ran at the reveal, Play offers the opening of a game, and every one
of those is a tap. A repertoire is what you have chosen to play, not what
you happened to survive.

**Optimise for fun.** A Run that just runs is the most fun, so nothing
interrupts one but a checkpoint you can tap through, and a game you want to
keep playing is yours to keep playing. Every mode pays points, the points
climb a milestone ladder, and each opening keeps its own record.

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

Under Autopilot a Run is always on a ten-second clock, with no hints and
nothing added. What changes from round to round is the opening, the colour,
where the round starts, and one of Run's own settings: what the opponent
steers toward. The player is told none of it; the bar says "Next Round" and
nothing else.

Most rounds start from move one and follow the player. The opening the
engine chose is only what the opponent steers toward: play something else
inside your prep and the round comes with you, re-steering from wherever you
take it (see Run). A move off your prep goes to the engine, as in any Run:
a blunder ends the round, and a sound one is a checkpoint. Now and then a
round is *steered* instead: it starts inside a family or a variation, with
the way in already on the board, dimmed, and your first decision is the
first move inside. That is how the engine drills one variation, and it is
kept rare. Home's Autopilot button says which the first round would be:
"Black, from move one", or the opening it would start inside.

Autopilot runs what you have and nothing else. With nothing prepared inside
the selection it says so and points at Growth, and Home's button does the
same; a new install builds its first line there, not here.

### The recommendation engine

`src/model/recommend.ts` ranks every candidate of (focus, opening, colour)
inside the selection. A focus is a preset of Run settings:

- **Test**: lines drawn by how often you would meet them. Whether the prep
  holds up when nothing says what it is.
- **Review**: lines drawn toward the positions you answer badly, have let
  lapse, are due on, or got wrong in your own games.

Both run what is there. There is no focus that adds to the repertoire: that
is Growth's, and the engine's answer to a selection with nothing prepared in
it is no round at all.

Each candidate is scored:

- **Need** is how loudly the work asks: cards due (a position your games got
  wrong counts as due), prep no run has tested. Each saturates, so two
  hundred due cards are not ten times louder than twenty.
- **Staleness** is how long that opening has gone without a round, measured
  against the other candidates rather than the clock. Candidates never played
  are all equally stale.
- **Freshness** (`src/model/freshness.ts`) is what the last few rounds were
  about. Every Run stamps the positions of the line it was drawn on with its
  round number, and a line is then read in two parts: its tail — the moves
  past where it last parts from another line, what makes it *this* line — and
  its head, what makes it this opening. A Test asks mostly as loudly as the
  stalest line in the opening has been left (fully stale after three rounds),
  so the line just built is run once and the other openings and a Review come
  round before it again; the draw prefers the line left longest, and never
  draws the line the last round was drawn on while there is another. Never
  silent, though: a quarter of the voice is kept, because a line just run is
  still a round when nothing else asks, and Autopilot has nothing but your
  lines to run. No schedule: forty lines cycle a rotating few.
- **Depth**: how far below the selection the opening sits, at 0.6 a level —
  the selection 1, a first move 0.6, a family 0.36, a variation 0.22. Most
  rounds are spent at the selection, from move one; a family left alone
  while the selection was just played still comes round, a fresh one does
  not.
- **Star**: an opening that is starred, or sits inside one that is, counts
  one level shallower.
- **Brake**: for every one of the session's last five rounds that was this
  focus, its weight is multiplied by 0.5. Counted over a window rather than
  consecutively, so a quieter focus still comes round after a run of the
  louder one. The session remembers its own rounds; nothing is saved.

Score is need × staleness × depth × brake. Need is measured on everything
inside an opening, so a family asks at least as loudly as any of its
variations. A Review that wins is then narrowed while a variation holds most
of its parent's work — half to step to a first move, two thirds to a family,
three quarters to a variation, a star taking a level off — so a round lands
on the variation that wants it and stays at the family when the need is
spread thin. A Test is never narrowed and is only ever the selection: what it
measures is whether the prep holds up when nothing says what it is. Only
openings the player has prep inside are candidates, the selection itself
included: a Review of the way in to an opening with nothing in it would be a
walk to the edge and a stop.

A round on a family or deeper starts inside it; one on the selection or a
first move starts from move one. A repertoire of one line per opening
concentrates all of its work at every level, and every Review would start
inside the deepest variation there is — so the session spaces them:
after a round steered into an opening below the selection, the next three
are drawn from the openings a round can start from move one. Steered rounds
are the exception, and stay one.

## Modes

### Run
One secret line, played until you blunder. Inside the region, a move keeps
you alive if it is in your repertoire or in the book. The opponent replies in
proportion to how often each move is played, confined to the region; on the
way in, confined to moves the book can still reach the opening from. Past the
end of the book your prep is the only referee, and reaching the end of the
prep completes the run.

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
board first, shown dimmed, earns nothing and reviews no cards, and is part of
the line the reveal offers. Autopilot uses this for its steered rounds; a Run
started by hand always begins at move one.

Every move of yours on a position your prep has an answer to is a review of
that position's card, graded by how long it took, so Run and Drill share one
schedule and a run does not ask again what it has just shown you know.

**Off your prep, the engine judges.** A move your prep does not have —
theory or not — is handed to the engine, which scores the position before
and after (`judgeByEval`, with `BLUNDER_LIMIT` of 80 centipawns). A blunder
ends the run. A sound move is a *checkpoint*, below the board: the verdict,
the move your prep had beside it, and two buttons — keep playing, or stop
here. Where your prep had a move, the miss is logged for Repair either way.
Stopping is the reveal; keeping playing hands the run over to the engine for
good.

**Past the hand-over** the engine is the referee and the game is a game: the
opponent plays the book by popularity while it has a move, because you are
still in the opening and the book is what you would actually meet, then the
engine at Play's Club level once it runs out. Your moves earn nothing — the
score is moves found in your prep — and nothing steers you back: once you are
out, you are out. Only a blunder, checkmate or a draw ends it. The clock
stops; the engine's score sits in the app bar instead.

**Where the prep ends** — your move, nothing prepared, the book still going —
is a checkpoint too. Reaching it completes the run and pays the finish bonus,
and the choice is the same: stop here and read the reveal, or keep playing
under the engine. Keeping playing is not leaving the prep, so a finish stays
green. Where nothing of yours passes through the region at all, the book is
the referee from the start and its end is the checkpoint.

That makes four endings, coloured apart: green (reached the end of the prep,
never left it), yellow (left the prep and played the game out to mate or a
draw), red (blundered), purple (stopped at a checkpoint out of prep).

With "new moves" left the run pauses at the edge instead and offers the
book's replies, with how often each is played; the one you choose is written
into the repertoire and the run carries on, up to the run's budget of new
moves. A chosen move earns nothing: the score is moves you found. This is
the one thing a run writes while it is played, and it is off by default.

The reveal: the line named, the board a replay of the whole line parked on
the position that ended it, the mistake in red beside the prepared move in
green. Nothing has been written. One button, *Keep this line*, says how many
moves it would add and adds them: every move the referee passed, and past
the hand-over only as far as the moves are still theory — a sound novelty is
a good move, not prep. A run that has nothing new to offer says so instead.

Options: steer toward (popular, weak spots, gaps), new moves (0 to 8), clock
(off, 10s, 30s a move), hints (the square a move starts from, never where it
lands). Autopilot sets the steer for itself and the rest to their defaults.

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
to, and you choose one from the book. A batch of answers is sized to how much
room the line has left — the same rule a Run uses at the edge of its prep
(`movesToFit`), halving the plies to the horizon and capped at eight — so a
hole at the second move is grown into a line and one near the end of the
opening is given the next move and no more. At the reveal, **Add more moves**
takes another batch, sized again from where the line now is; nothing carries
on by itself. Holes are only counted inside the region, and on the way into
it. This is the picker a Run with new moves opens at the edge of the prep, as
a mode of its own.

It is also where a repertoire starts, since Autopilot builds nothing. A side
with no tree yet is grown from nothing: as Black, the first moves you would
meet are the first holes, from move one; as White, your first move is not a
reply to anything, so the lobby offers the book's first moves and Black's
answers to the one you keep are the holes from there. Home's Autopilot
button opens Growth while there is nothing to drill.

### Repair
The positions your games got wrong, compared against the repertoire: off prep
(you had a move and played another) and unprepared (you kept reaching it with
nothing). Imported games and games played in Play both count, and so do slips
made in the app. Scoped to the region. Under Autopilot the same evidence
steers Run instead: a slip makes its position a weak spot, and one your games
got wrong counts as due.

### Play
A game against the engine at a chosen strength. While the game is still on the
selected opening's move order the engine plays that move order, so a game in
the Najdorf is a Najdorf; past it the engine plays for itself. Every finished
game — mate, a draw or a resignation — is kept as a game, in the same shape
as an import, so Repair, coverage and the engine read what you actually play:
the newest two hundred, cut to their openings. The opening can be saved into
the repertoire when the game ends, and that is a button, not a side effect.

## Score

Points are reward, not assessment. Nothing is ever subtracted. All the numbers
live in `POINTS` in `src/model/scoring.ts`.

| Mode | Per action | Bonuses |
|---|---|---|
| Run | 1 per correct move in your prep | +5 reaching the end of the prep, +3 more for green; speed; combo. Nothing past the hand-over |
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

A new install starts empty, and nothing writes into it unasked. Growth
answers the replies you have none for, a Run offers the line it ran at the
reveal, Play offers the opening of a game; each is a tap, and a Run with new
moves allowed writes the ones you choose at its edge.

## Analysis

Board, engine lines, eval bar, PGN in and out, and the reference explorer
underneath: move frequencies, results, opening names, a handful of master
games, and the named book lines the app knows from the current position, each
with a summary and ideas and one tap to add.

## Import your games

**Repertoire → Import** pulls recent games from Lichess or Chess.com, or a
pasted PGN, and feeds Repair alongside the games played in Play. A published
Claude Artifact runs under a CSP that blocks cross-origin requests, so the
live fetch fails there; pasting a PGN and a bundled synthetic sample archive
both work anyway.

## Data

State lives in IndexedDB (with a localStorage fallback) and, when the page runs
as a published Artifact, in the `db` runtime capability against your Claude
account — inside the artifact sandbox that is the only thing that persists.
Startup reads the account copy before deciding anything. The document is
gzipped and base64-encoded and capped at 256 KiB by the platform; the app says
so in Settings when it overflows.

Saved state carries a schema version. Version 0 is the fresh start: every
earlier save, settings included, is discarded rather than migrated.

Imported games stay on the device: bulky, re-importable, and the document
has to fit. Games played in Play go with the state — there is nowhere to
re-import them from — capped at two hundred and cut to forty plies, and two
devices' games are merged by id.

The reference database is crawled from the [Lichess opening
explorer](https://explorer.lichess.ovh) — rated 2000–2500 blitz, rapid and
classical games — and lives in `src/model/book/book.json`.

`scripts/fetch-book.mjs` does the crawl. It is best-first: the most-played
unexpanded position is always the next one requested, so depth and breadth fall
out of a single budget rather than being configured, and the popular lines get
deep on their own. Positions are keyed and de-duplicated locally, so a position
two move orders reach is crawled once and the transposition is free. Pacing
adapts to the explorer's throttling, and the run checkpoints, so raising the
budget continues from the frontier instead of starting again:

```bash
set -a; . ./.env.local; set +a   # LICHESS_TOKEN=...
node scripts/fetch-book.mjs 8000
```

Move popularity is stored as a share of the position in basis points rather
than an absolute count: the explorer only ever shows it as a proportion, and at
this sample size the absolute numbers are nine digits each. `src/model/book.ts`
decodes the file into the index the app reads; because the crawl already knows
every position's key, building the index is a parse and two loops with no move
generation at all.

The seeded repertoires in `src/model/seed/repertoires.ts` supply each
repertoire's character by hand and take their coverage from the book: `store/
seed.ts` extends them until nothing played in 3% of games or more goes
unanswered, which is the same guarantee `coverage.test.ts` checks.

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
