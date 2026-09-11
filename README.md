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
npm test             # 134 tests: chess rules, tree, SRS, PGN, analysis, seed data
npm run typecheck
npm run build        # production build into dist/
npm run artifact     # repackage dist/ for publishing as a Claude Artifact
```

## What is in here

### Train
The main loop. A position appears, the app asks **what do you play here?**, you
play a move on the board, and it compares it against your repertoire.

- Right: ✓ plus Again / Hard / Good / Easy, each labelled with when the position
  comes back.
- Wrong: your repertoire's move next to the one you played, with **Show why**
  (the continuation) and **Explore** (the reference database) one tap away. A
  wrong answer is graded `again` automatically — you spend your attention on
  understanding, not on a button.
- No engine evaluations during recall by default. This is memory retrieval.
- "Follow the line after a correct answer" (Settings, on by default) plays the
  opponent's reply and asks the next move in the same line, so you can compare
  line-running against pure position-by-position drilling.

Scheduling is a small SM-2 variant in `src/model/srs.ts`: learning steps of 1
and 10 minutes, ease from 1.3 up, halved interval after a lapse, no interval
fuzz. `review()` is pure and deterministic, so the whole algorithm can be
swapped without touching the UI.

### Repertoire
Three seeded repertoires (White 1.e4; Black Najdorf vs 1.e4; Black Nimzo/QID vs
1.d4) — about 460 trainable decision points in total.

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
Seventeen named book lines (Poisoned Pawn, English Attack, Yugoslav, Berlin,
Botvinnik Semi-Slav, Mar del Plata…) each with a summary and the ideas behind
them. **Add to repertoire** lets you trim the line first — tap any move to set
the cut-off, because usually you want the idea and not twenty plies of theory.

### Analysis
Board, move list, eval bar, three engine lines, PGN in and out. Real Stockfish
(the asm.js build, in a Web Worker) with a small built-in evaluator as a
fallback if the worker cannot start. Secondary to training on purpose.

### Import your games
`Repertoire → ⤓` pulls your recent games from Lichess or Chess.com and compares
them against your repertoire:

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

Everything is local: IndexedDB via `idb-keyval`, with a localStorage fallback
and an in-memory last resort. Reload-safe, nothing leaves the device, no
backend. Settings → Reset restores the seeded state.

The reference database is a small curated sample, authored as ~250 weighted
paths in `src/model/seed/openingPaths.ts` and folded into a tree at runtime, so
the numbers are internally consistent: a move is never shown as more popular
than the position it comes from. Every seeded line — repertoires, book lines,
master games — is checked for legality by the test suite.

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
