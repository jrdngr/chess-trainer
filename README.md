# Repertoire Trainer

A mobile-first chess opening repertoire trainer. Build a repertoire as a move
tree, drill it position by position with spaced repetition, and explore
reference theory without leaving the training loop.

This is a **UX prototype**, not a product. It exists to answer questions about
what the eventual native app should be.

## Run it

```bash
npm install
npm run dev          # http://localhost:5173, also served on your LAN IP
```

`npm run dev` binds to `0.0.0.0`, so a phone on the same Wi-Fi can open
`http://<your-laptop-ip>:5173`. On iOS, Share → Add to Home Screen gives a
full-screen, chrome-free app.

```bash
npm test             # 248 tests: chess rules, tree, SRS, PGN, analysis, permadeath, seed data
npm run typecheck
npm run build        # production build into dist/
npm run artifact     # repackage dist/ for publishing as a Claude Artifact
```

## What is in here

### Train
The main loop. A position appears with the side to move, you play a move on
the board, and it is checked against your repertoire.

- Right: **Correct** plus **Guessed / Hard / Knew it / Easy**. The stored grades
  are Anki's, but "again" and "good" name buttons in a spaced-repetition app
  rather than what just happened in your head; these say you did not really know
  it, you got there, you knew it, it was instant. No "comes back in 4d" caption
  under each one — the number is noise at the moment you are being asked how
  well you knew something.
- Wrong: your repertoire's move next to the one you played, both drawn on the
  board — yours in red, the prepared one in green — with **Why?**, **Show line**
  (the continuation) and **Explore** (the reference database) one tap away. A
  wrong answer is graded `again` automatically — you spend your attention on
  understanding, not on a button.
- **Why?** answers the question the red square does not. "It isn't in your
  repertoire" is a fact, not a reason, so the engine plays the position on from
  the move you made and shows the reply that punishes it, beside what the
  prepared move was worth. The refutation is a line on a board you can step
  through rather than a verdict — five moves a side — and the footer says which
  engine gave it and at what depth, because a shallow opinion should look like
  one.
- No engine evaluations during recall by default. This is memory retrieval.
- "Follow the line" (Settings, on by default) plays the opponent's reply and
  asks the next move in the same line, so you can compare line-running against
  pure position-by-position drilling.

A session has no length. It keeps drawing positions until you stop it, with
**Stop** next to Moves and Explore and the close button doing the same thing;
stopping shows the summary rather than dumping you out, and **Keep going**
resumes. Scheduled work comes first — due reviews, learning cards, then new
material — and once the schedule is clear the session serves the positions you
have looked at least recently, marked *extra practice* so you know where you
are.

That only works because answering early cannot push the schedule out: a correct
answer on a card that is not due yet keeps the date it already had. Getting it
wrong early still pulls it in. Without that, a long session would quietly
scatter your whole deck into next month.

Scheduling is a small SM-2 variant in `src/model/srs.ts`: learning steps of 1
and 10 minutes, ease from 1.3 up, halved interval after a lapse, no interval
fuzz. `review()` is pure and deterministic, so the whole algorithm can be
swapped without touching the UI.

### Permadeath
One line, drawn in secret, played until your first mistake. Nothing on screen
names it while you play — no opening name, no move list, no explore. Dying is
what buys you the reveal, which names the variation, gives its ECO code and
prints the line in full, including how it would have gone on.

The setup screen decides the run. **Start run** sits at the top, above the
options, so the common case — same rules as last time — is one tap. Everything
past the first two sections is off by default; the plain mode is a line from your
repertoire, no clock, no help. Choices are remembered between runs.

- **Play as** — White, Black, or random.
- **Lines** — your repertoire, one named opening, or the whole reference
  database. Book is the most forgiving: any move somebody has played here keeps
  you alive, and the opponent replies in proportion to how often each move is
  played.
- **Openings** — pick one opening and play it out. The opponent walks you into
  it, and while you are still inside its move order that move order is the only
  thing that counts, for both sides, because it is what makes the opening that
  opening; past the end of it the book takes over. **All openings** lists all 163
  named openings sorted by how often they are actually played, searchable by
  name, ECO or moves. Starring one keeps it on the setup screen, and starred
  openings sit at the top of the full list. Names that only say what the first
  move was are left out: "King's Pawn Opening" is not an opening you sit down to
  practise, it is the whole database with a first move, which Book already is.
- **Opening** — narrow the draw to one repertoire instead of all of them.
  Picking one settles which side you are on, so the colour follows it.
- **Clock** — 10 or 30 seconds a move, or three minutes for the whole run. Only
  your own thinking is charged; the opponent's reply is free. Running out ends
  the run exactly like a wrong move does.
- **Hints** — a budget of one or three for the run. A hint names the square the
  move starts from and never where it lands, so it narrows the position without
  answering it. Hints spent are shown on the reveal.
- **Target weak spots** — bias the draw toward lines you get wrong, have lapsed
  on, or have let fall overdue, read straight off the review schedule.
- **Play the other side** — sit on the side your repertoire prepares *against*,
  and stay alive by knowing what your opponent is meant to do. A reversed run
  is judged on positions that are not your decision points, so it is kept out
  of the review schedule entirely.
- **Extended mode** — the run does not stop when the prep does. The engine takes
  over the judging and you survive as long as your moves stay sound, so a line
  that ends the moment the setup is complete becomes a game you can still lose.
  A move that drops more than 0.80 ends the run as a blunder; the threshold is
  generous on purpose, because past the prep there is no single right move and a
  mode that ended a run over a quarter of a pawn would be judging taste. Your
  own moves keep counting towards the score, the header shows the live
  evaluation, and hints are not offered — there is no prepared move to point at.
- **Per-opening records** — a separate best for each opening and side, rather
  than one number across everything.

A line is drawn in proportion to how often you would actually meet it. Where
the *opponent* chooses, the reference database decides: a King's Indian arrives
through 1.d4 2.c4 far more often than through 1.b4, and weighting by that cuts
runs that turn on a reply played less than 5% of the time from a quarter to a
sixth. Where *you* choose between prepared alternatives the split is even, so a
heavily branched mainline cannot swamp everything else — your own alternatives
multiply lines without making a position any likelier to appear on a board. Rare
sidelines keep a floor rather than vanishing: they are prep too.

Any move you have prepared from a position counts, not just the one the drawn
line happens to continue.

Playing a move that is real theory but not in your prep is not a loss. The run
pauses, names the line your move leads into, shows what your prep had instead,
and offers three ways on: **add it to your repertoire and carry on**, carry on
without adding it, or stop there. Carrying on keeps the move, keeps the score,
and hands the judging to the book for the rest of the run — the prep is behind
you, so the book is the only honest referee left. Only a move nobody has played
is still a plain loss.

That makes four endings rather than two, and they are coloured apart, because
"learn this" and "you got that wrong" are different notes:

| | |
|---|---|
| **Green** | finished the line, all of it inside your prep |
| **Yellow** | finished, having stepped out of prep along the way |
| **Red** | played a move that is neither prepared nor in the book |
| **Purple** | the run ended out of prep |

The record counts endings by grade and shows them as a bar, so a run of purple
says something a run of red does not: the prep has gaps, not the recall.

When a run ends, the board becomes a replay. Arrows and a tappable move strip
walk the whole line, starting parked on the position that ended it — step
forward to see how it was meant to continue, or back to see how you got there.
The strip colours what happened: your own moves, the opponent's, the move that
ended the run in red beside the prepared move in green (both carrying the same
move number, which is nobody's notation but the only honest way to show a pair),
and the rest of the line in grey. **Copy the moves I played** puts the game as
played on the clipboard — not the continuation — for pasting somewhere.
The mistake's red and green squares are shown only on that one position, so
stepping away does not leave stale marks behind.

A line played out in full offers **Continue in extended mode** above **New run**
and **Play from here**. It is the better continuation of the two: it carries the
*run* on rather than starting a friendly game, so the score keeps counting and a
blunder still ends it. Logging that run again amends the entry the completed
line already made instead of counting a second run — and reaching the end of a
line is a fact, so carrying on past it and blundering does not unmake it. It is
offered only where the prep ran out, not where you went wrong: there the run
ended because of a mistake, and there is still prep to learn.

**Play from here** carries the position on the board on against the engine —
Stockfish if its worker starts, the heuristic evaluator otherwise. This is the
answer to a line that stops just as it gets interesting: repertoire prep ends
where prep ends, and the honest continuation is a game, not more prep. You keep
your own colour, the engine answers with a short fixed think, moves can be taken
back a pair at a time, and nothing that happens there touches your record or
your schedule. The engine runs here whether or not evaluations are switched on
elsewhere — playing on *is* the engine.

Only the move that ends a run touches the schedule, graded `again`. The correct
moves before it are primed by the ones before them, so crediting them would
inflate intervals on weaker evidence than an isolated review gives.

### Repertoire
Three seeded repertoires built around what you actually play — the **Queen's
Gambit** with White, and the **King's Indian** (vs 1.d4) and **Sicilian Dragon**
(vs 1.e4) with Black.

White answers 1...d5 with 2.c4 and covers the QGD (Exchange, with the minority
attack), Slav, Semi-Slav (Botvinnik and Meran), QGA, Tarrasch, Chigorin, Albin
and Baltic, plus every Indian defence after 1...Nf6: King's Indian, Grünfeld,
Nimzo, Benoni, Benko, Budapest, Old Indian and the Dutch.

Black answers 1.d4 with the King's Indian — Classical (Mar del Plata, Bayonet,
Petrosian, Exchange, Gligorić), Sämisch, Averbakh, Four Pawns, Makogonov,
Fianchetto, the London and Torre anti-KID set-ups, and the c4/Nf3/g3 move orders
that transpose — and answers 1.e4 with the Sicilian Dragon: the Yugoslav Attack
(including the Soltis main line and the 9.O-O-O ...d5 break), Classical,
Levenfish, fianchetto, and every anti-Sicilian worth the name (Moscow, Alapin,
Closed, Grand Prix, Smith-Morra, the King's Indian Attack and 2.c4).

The Dragon is chosen deliberately: it is the King's Indian's structural cousin —
same ...g6/...Bg7 fianchetto, same opposite-castling race logic — so the two
halves of the Black repertoire reinforce each other.

Within a repertoire there is exactly one move for you in any given position — a
repertoire is a set of decisions, not a menu — and a test enforces it. All the
breadth is on the opponent's side.

**Coverage is checked, not claimed.** `src/model/seed/coverage.test.ts` walks
every position the repertoire reaches where the opponent is to move and prep
already exists, and fails if any reply played in ≥3% of reference games has no
prepared answer. Positions are merged by key first, exactly as training does, so
a line covered through one move order counts through all of them. A line simply
ending is not a hole — that is prep running out, not prep disagreeing with
itself.

The opening position is checked per colour rather than per repertoire, so a
Black repertoire is allowed to answer only 1.d4 as long as a sibling repertoire
answers 1.e4. There are no accepted gaps left.

Browse by playing moves on the board. Playing a move the tree does not have
offers to add it. Each move has a sheet: make it the main move, note why you
play it, reorder it, train just that branch, or delete the branch. Underneath
the move list, the reference database shows what the book plays here — tap to
add straight into the tree.

Transpositions collapse: the same position reached two ways is one card, and
both routes' moves are offered as valid answers.

### Explore
The reference database, as an opening explorer: move frequencies, win/draw/loss
splits, opening names and ECO codes, and a handful of real master games.
Twenty-eight named book lines — Mar del Plata, Bayonet, Sämisch, Fianchetto,
Four Pawns, Averbakh, the KID Exchange, Slav main line, Meran, Botvinnik, QGA
Classical, Tarrasch, Chigorin and more — each with a summary and the ideas
behind it. **Add** lets you trim the line first — tap any move to set the cut-off,
because usually you want the idea and not twenty plies of theory.

### Analysis
Board, move list, eval bar, three engine lines, PGN in and out. Real Stockfish
(the asm.js build, in a Web Worker) with a small built-in evaluator as a
fallback if the worker cannot start. Secondary to training on purpose.

### Import your games
**Repertoire → Import** pulls your recent games from Lichess or Chess.com and
compares them against your repertoire:

- **Gaps** — positions you reach often with nothing prepared
- **Deviations** — positions where you played something other than your prep
- **Coverage** — how many games stayed in book, and the average ply you left it

Any finding can be added to the repertoire in one tap, and immediately enters
the review queue.

> **Network note.** The live API clients are real and work when the app runs
> from a normal origin. A published Claude Artifact runs under a CSP that blocks
> every cross-origin request, so the fetch fails there before it leaves the
> page. Two offline paths cover it: **paste a PGN export** (same analysis
> pipeline, no network) and a **bundled sample archive** of 60 generated games
> so the flow is explorable anyway. The sample games are synthetic — they are
> not anyone's real games.

## Data

**Where state actually lives depends on the viewer, and that matters.** Artifacts
are framed with a sandbox that withholds `allow-same-origin`, so the frame's
origin is opaque and touching `localStorage` or `indexedDB` throws
`SecurityError` — not "returns empty", *throws*. A store that swallows that
error keeps working and forgets everything on close, which is the worst possible
failure for a trainer. So the app probes both backends at startup and treats the
`db` runtime capability as the primary store when they are unavailable, which
inside a published artifact is the normal case.

The local store is IndexedDB via `idb-keyval`, with a localStorage fallback and
an in-memory last resort. Reload-safe wherever it is allowed to run. Settings → Reset restores the
seeded state. Saved state carries a schema version; when the seed data changes,
an older save is discarded rather than migrated, and your settings are kept.

**The account store.** When the page runs as a published Artifact it asks for
the `db` runtime capability and keeps your state against your Claude account —
both so a session started on a phone continues on a laptop, and because in the
sandbox it is the only thing that persists at all. Startup reads the account copy
*before* deciding anything, so a freshly seeded state can never overwrite real
progress; pushes are held back until that reconcile completes.

If neither backend works, the Train screen says **"Progress isn't being saved"**
with a one-tap fix rather than quietly resetting.

A db document holds at most 256 KiB and a fully-trained state is ~1.8 MB of JSON
(mostly FENs, which repeat heavily), so the payload is gzipped via
`CompressionStream` and base64-encoded — about 135 KiB in practice, and the size
is checked before each write rather than discovered as a rejection. Imported
games are deliberately left out of the sync: bulky, re-importable, and they would
eat the headroom.

Conflict handling is whole-state last-write-wins by timestamp. That is the right
model for one person on two devices and honest about what it does not do: it
does not merge two sessions reviewed concurrently. Settings shows the sync state
and says so. Where the capability is absent — running locally, an older runtime,
a viewer who declines — `claude.use('db')` resolves null and the app is local
only, and the Sync row in Settings says so.

The reference database is a small curated sample, authored as ~320 weighted
paths in `src/model/seed/openingPaths.ts`, weighted towards the Queen's Gambit
and King's Indian and folded into a tree at runtime, so
the numbers are internally consistent: a move is never shown as more popular
than the position it comes from. Every seeded line — repertoires, book lines,
master games — is checked for legality by the test suite.

## Design

Dark, borderless surfaces on a near-black ground, one indigo accent, white
primary buttons, iOS-style large titles and grouped lists. Tokens live at the
top of `src/styles.css`; the board palettes and highlights in
`src/components/board.css`. Copy is kept to a few words per element.

## Layout

```
src/
  chess/       rules, position keys, PGN parsing with variations
  model/       repertoire tree, SRS, session building, reference index,
               game analysis, permadeath rules, seed data
  engine/      Stockfish worker + heuristic fallback behind one interface
  store/       zustand store, IndexedDB persistence, cloud sync, seed loading
  components/  board, pieces, explorer, sheets, icons, and the shared
               controls (app bar, toggles, segmented rows, move strip)
  screens/     Train, Repertoire, Explore, Analysis, Import, Settings
  screens/permadeath/
               setup, the live run, the reveal, play-on, the record, and
               the clock and engine-referee hooks
```

Train and Permadeath sit side by side on the Train screen as two equal modes,
each with its own hero and its own start button.

Screens are built from a small set of shared pieces in `components/ui.tsx` —
`AppBar`, `Section`, `Toggle`, `Stepper`, `Segmented`, `ChoiceRow`, `Strip` —
so a new screen has nothing to invent. Layout comes from utility classes in
`styles.css` (`.actions`, `.note`, `.mt-*`) rather than inline styles.

The board is hand-written rather than pulled from a library: tap-tap and drag
both work, legal moves show as dots, captures as rings, pieces animate between
squares, promotion is a sheet, and pieces are inline SVG so nothing is fetched
at runtime.

## Questions this prototype is meant to answer

Position-by-position vs line-running. How much to show after a wrong answer.
Whether Again/Hard/Good/Easy reads naturally for chess. Whether the reference
database belongs in a bottom sheet or its own screen. Whether "add to
repertoire" with a trim step is the right import gesture. When the engine should
be available at all. How to communicate what is due, and what your coverage
actually is.

Nothing here is load-bearing. Change it.
