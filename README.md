# Repertoire Trainer

A mobile-first chess opening trainer built around one idea: you are never
forced down a line. You pick a side and a region of the opening tree — the
whole book, one first move, a family like the King's Indian, or a single
variation — and every mode works inside it. Inside your prep a move keeps you
alive if it is prepared or it is theory; outside it the engine judges, and
only a blunder ends the game. Autopilot plays round after round on what you
have, the repertoire grows only when you say so, every starred opening carries
a rating that rises and falls with what you remember, and Tidy points out
where your lines could converge.

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

**Autopilot is the main loop.** A round can repeat what needs repeating by
steering the opponent toward it, so a recommendation engine chooses an
opening inside the selection, a colour, and what the opponent steers toward,
one round after another, with no trip back to Home in between and no end
until you stop. The settings are the engine's business and nothing on screen
names them. The other modes stay selectable by hand, each with its own setup,
for training on your own terms.

**Autopilot drills; it never builds.** Nothing is written into the
repertoire by playing. Growth is where lines are built, an Autopilot round
offers the line it ran when it ends, Play offers the opening of a game, Tidy
offers switches, and every one of those is a tap. A repertoire is what you have chosen to play, not what
you happened to survive.

**Optimize for fun.** A round that just runs is the most fun, so nothing
interrupts one but a checkpoint you can tap through, and a game you want to
keep playing is yours to keep playing. Each starred opening keeps its own
rating, and Survival keeps a best for every opening a game passes through.

## Run it

```bash
npm install
npm run dev          # http://localhost:5173, also served on your LAN IP
```

`npm run dev` binds to `0.0.0.0`, so a phone on the same Wi-Fi can open
`http://<your-laptop-ip>:5173`. On iOS, Share → Add to Home Screen gives a
full-screen, chrome-free app.

```bash
npm test             # chess rules, tree, SRS, PGN, analysis, rounds, regions, ratings, nudges, Tidy
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

Autopilot plays one round after another. When one ends, the end-of-round
screen has **Next run** right under the board, and one tap starts the next
round — the screen is worth reading, so nothing starts on its own.
The rating moves at the top of the screen as it is earned, so nothing sums a
round up again. A session never ends on its own. Stop is the close button in
the app bar, and stopping goes Home, as leaving any mode does.

A round is always on a ten-second clock, with no hints and nothing added.
What changes from round to round is the opening, the colour, where the round
starts, and what the opponent steers toward. The player is told none of it;
the button says "Next run" and nothing else.

Most rounds start from move one and follow the player. The opening the
engine chose is only what the opponent steers toward: play something else
inside your prep and the round comes with you, re-steering from wherever you
take it (see The round). A move off your prep goes to the engine: a blunder
ends the round, and a sound one is a checkpoint. Now and then a
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
inside the selection. A focus is a preset of round settings:

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
  about. Every round stamps the positions of the line it was drawn on with its
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

### The round
Autopilot's rounds follow one secret line, played until you blunder. Inside
the region, a move keeps you alive if it is in your repertoire or in the book.
The opponent replies in proportion to how often each move is played, confined
to the region; on the way in, confined to moves the book can still reach the
opening from. Past the end of the book your prep is the only referee, and
reaching the end of the prep completes the round.

Where you have prepared lines through the region, one is drawn to steer the
opponent: by how often you would actually meet each line, or tilted hard
toward positions you answer badly, have let lapse, or got wrong in your own
games, as the recommendation engine chooses. Where you have no lines, the
opponent walks you down the opening's own move order.

The drawn line is not a fence. Any move that stays inside the region is
accepted, and when yours leaves the line a new one is drawn from where you
now are, by the same steer, so the opponent keeps steering rather than
wandering. A line reached by a transposition counts. Only where nothing of
yours passes through the position does the opponent fall back to the book,
by popularity.

A round can also start *inside* an opening: the way in is played onto the
board first, shown dimmed, rates nothing and reviews no cards, and is part of
the line the round offers to keep.

Every move of yours on a position your prep has an answer to is a review of
that position's card, graded by how long it took, so Autopilot and Drill
share one schedule and a round does not ask again what it has just shown you
know.

**Off your prep, the engine judges.** A move your prep does not have —
theory or not — is handed to the engine, which scores it against the best
move in the same position (`judgeByEval`, with `BLUNDER_LIMIT` of 80
centipawns). A blunder ends the round. A sound move is a *checkpoint*: the
round stops there, with your move beside the one your prep had. Where your
prep had a move, the miss is logged for Repair either way and costs rating.
When the move you played was closer to the rest of your lines than the
prepared one, by the rules Growth's arrows use, a line under the board says
so and **Tidy this** opens Tidy on that position. **Keep playing** plays your
move and hands the round over to the engine for good.

**Past the hand-over** the engine is the referee and the game is a game: the
opponent plays the book by popularity while it has a move, then the engine at
Play's Club level once it runs out. Nothing is rated and nothing steers you
back. Only a blunder, checkmate or a draw ends it.

**Where the prep ends** — your move, nothing prepared, the book still going —
is a checkpoint too. Keeping playing is not leaving the prep, so a finish
stays green. Where nothing of yours passes through the region at all, the
book is the referee from the start and its end is the checkpoint. A clean end
of prep can offer to grow the opening (**Grow it**) or the line (**Grow this
line**, at the bottom of the screen).

That makes four endings, colored apart: green (reached the end of the prep,
never left it), yellow (left the prep and played the game out to mate or a
draw), red (blundered), purple (stopped at a checkpoint out of prep).

A round ends on one screen, however it ends, and is logged once as it opens:
keep playing and end again, and only its grade changes. The verdict flashes
over the board for two seconds. Right under the board, always in the same
place, are **Keep playing** and **Next run**; after a blunder or a miss,
**Analyze** opens the game in the Analysis tab. Below them: the board a replay
of the whole line, parked on the position that ended it — on a miss, the
position you were asked about, dimmed, with your move in red beside the
prepared move in green — and the line named. Nothing has been written. One
button, *Keep this line*, says how many moves it would add and adds them:
every move the referee passed, and past the hand-over only as far as the
moves are still theory.

### Survival
From move one, through your prep and on past it, until your first blunder.
The score is moves survived: a best for every opening the game went through,
recent form beside it, and one best overall. A sound move where your prep had
another does not end the run: the miss flashes over the board with the
prepared move in green, is logged for Autopilot's review and Repair, and is
listed at the end, where a miss that was closer to your other lines than your
prep gets the same **Tidy this** line as Autopilot. Survival never rates and
never adds to the repertoire.

Steer: *My lines* (the opponent plays into your prep, tilted toward the lines
you miss most), *My gaps* (it heads for a reply you have no answer to, and
the run keeps going past it) or *Ignore my lines* (the book by popularity from
move one). Clock: off, 10s or 30s a move.

A gaps run draws the hole it walks to on how often you would actually meet it:
the reply's share of its position, times the share of games that reach the
position at all — every opponent choice on the way, multiplied together. Your
own moves cost nothing, because you are the one making them. It is drawn
rather than taken in order, but only from the holes worth at least an eighth
of the best one (`DRAW_WINDOW`), so the common replies are covered first and
the obscure ones arrive when there is nothing commoner left to do.

### Drill
Positions inside the region, drawn from the schedule: due first, then new,
then extra practice. Right earns a grade of Guessed / Hard / Knew it / Easy;
wrong is graded `again` automatically and offers **Why?**, **Show line** and
**Explore**. "Follow the line" keeps going after a correct move. A session has
no length: it ends when you end it.

Scheduling is a small SM-2 variant in `src/model/srs.ts`. Answering early
never pushes a card out.

### Growth
A run starts standing on the reply you have no answer to that you would meet
most, and you choose an answer from the book. A batch of answers is sized to
how much room the line has left (`movesToFit`, halving the plies to the
horizon and capped at eight), so a hole at the second move is grown into a
line and one near the end of the opening is given the next move and no more.
At the reveal, **Add more moves** takes another batch, sized again from where
the line now is; nothing carries on by itself. Holes are only counted inside
the region, and on the way into it.

**The arrows lean toward a narrow repertoire** (`src/model/nudge.ts`). Green
is the familiar move: one that transposes into a position you have, one that
heads there a move of yours later, or a habit — a move you choose around the
same point (within four plies) in this opening or its kin at least twice, and
at least as often as you pass it over. Kin are hand-listed in
`src/model/kin.ts`: the Catalan shares its fianchetto with the English and the
Réti and its center with the Queen's Gambit Declined, so a new opening already
knows your habits from its neighbors. Yellow is a familiar move the board
would not draw — ranked too low, or not in the book at all, in which case the
engine must pass it first and the reason says "not in the book". Red is the
move that closes off lines you could still reach, or one you keep passing
over. Which kind of familiarity wins is a setting (transpositions or habits).

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
steers the rounds instead: a slip makes its position a weak spot, and one your games
got wrong counts as due.

### Play
A game against the engine at a chosen strength. While the game is still on the
selected opening's move order the engine plays that move order, so a game in
the Najdorf is a Najdorf; past it the engine plays for itself. Every finished
game — mate, a draw or a resignation — is kept as a game, in the same shape
as an import, so Repair, coverage and the engine read what you actually play:
the newest two hundred, cut to their openings. The opening can be saved into
the repertoire when the game ends, and that is a button, not a side effect.

## Ratings

There is no global score. Each starred opening carries a chess-style rating,
and only Autopilot moves it: every prepared position answered is one result,
`rating + 40 × (result − expected)` with the expected score logistic at a
scale of 450, starting at 0 and never below it. It settles at the accuracy you
actually hold. A result rates every starred opening the line is inside,
transpositions included, and a miss is credited to the position you were
asked about. Drill, Growth, Repair, Play and Survival are recorded but never
rated.

The ladder is six pieces: Pawn 100, Knight 250, Bishop 400, Rook 550, Queen
700, King 850 — roughly 63, 78, 89, 94, 97 and 99% accuracy. Below Pawn reads
"Unrated". A bar slides in at the top when a rating moves; tapping it opens
Stats. The clock is pressure only: nothing is paid for speed.

## Tidy

A tab of its own, under the selection bar like Home. It looks at every move
you have chosen inside the selection and asks whether another move there is
closer to the rest of your lines, by the arrows' rules: it transposes into
them, heads toward them, or is what you play around that point in your other
lines while yours is played nowhere else. Your own move is judged as if its
line were gone, so it gets no credit for being the line it already is.
Captures are never switched for a habit.

Each find shows the position, your move against the suggestion in Growth's
colors, and why. Finds are listed biggest savings first. A suggestion the book
does not have waits on the engine and drops out if it fails. **Switch** makes
the suggestion your move and removes yours with everything under it, with
Undo in the toast. The position starts over: its review card is new again and
its logged mistakes go, while ratings stand. A find opened from the end of a
round is pinned at the top, open.

## Stats

The Stats tab leads with your starred openings by rating, then activity: the
streak, rounds a day and rounds by mode over a chosen window. Each opening has
a page with its rating over time, a seven-day accuracy average, its
*favouriteness* — its rank among the siblings you have actually played, by
rounds in the last thirty days — and the variations under it. A round is one
Autopilot round, one Survival run, one Drill session, one Growth run or one
Repair sitting: none of them is a game of chess, so none is called one. Every row in the
opening picker opens its page too. History is kept for ever.

## Repertoire

One tree per colour. Openings are derived from the tree rather than stored:
an opening is the region beginning where the book starts naming the position.
Transpositions collapse to one card. Browse by playing moves; each move has a
sheet to prefer it, note it, reorder it, train the branch, or delete it. The
reference database sits under the move list.

A new install starts empty, and nothing writes into it unasked. Growth
answers the replies you have none for, an Autopilot round offers the line it
ran, Play offers the opening of a game, and Tidy offers switches; each is a
tap.

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
  model/       opening tree and regions, selection, round rules, SRS, session
               building, ratings, stats series, the recommendation engine,
               growth, nudges and kin, tidy, survival, repair, reference
               index, seed data
  engine/      Stockfish worker + heuristic fallback behind one interface
  store/       zustand store, IndexedDB persistence, cloud sync, the engine's input
  components/  board, pieces, explorer, the selection bar and pickers, the
               score bar, the move clock, charts, sheets, icons, shared controls
  screens/     Home, Repertoire, Tidy, Stats, Analysis, Import, Settings, and
               one folder per mode: autopilot, openingRun (Autopilot's round),
               survival, drill, growth, repair, play
```
