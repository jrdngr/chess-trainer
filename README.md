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
npm test             # 161 tests: chess rules, tree, SRS, PGN, analysis, seed data
npm run typecheck
npm run build        # production build into dist/
npm run artifact     # repackage dist/ for publishing as a Claude Artifact
```

## What is in here

### Train
The main loop. A position appears with the side to move, you play a move on
the board, and it is checked against your repertoire.

- Right: **Correct** plus Again / Hard / Good / Easy, each labelled with when
  the position comes back.
- Wrong: your repertoire's move next to the one you played, with **Show line**
  (the continuation) and **Explore** (the reference database) one tap away. A
  wrong answer is graded `again` automatically — you spend your attention on
  understanding, not on a button.
- No engine evaluations during recall by default. This is memory retrieval.
- "Follow the line" (Settings, on by default) plays the opponent's reply and
  asks the next move in the same line, so you can compare line-running against
  pure position-by-position drilling.

Scheduling is a small SM-2 variant in `src/model/srs.ts`: learning steps of 1
and 10 minutes, ease from 1.3 up, halved interval after a lapse, no interval
fuzz. `review()` is pure and deterministic, so the whole algorithm can be
swapped without touching the UI.

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
               game analysis, seed data
  engine/      Stockfish worker + heuristic fallback behind one interface
  store/       zustand store, IndexedDB persistence, seed loading
  components/  board, pieces, explorer, sheets, icons
  screens/     Train, Repertoire, Explore, Analysis, Import, Settings
```

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
