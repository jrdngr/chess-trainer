# Browser safety net

Recorded sessions of the real app, one per mode, that replay identically every
run. They guard phase 1 of the native port (see `docs/native-port/plan.md`):
the run logic is being moved out of the screens, and any change in what a
screen says or saves shows up here as a diff.

```bash
npm run e2e          # replay and compare
npm run e2e -- -u    # re-record after an intended change, then review the diff
```

Each test writes two files to `traces/`: one line per step (the step, the
board's FEN and the screen's text), and the saved state at the end.

What makes a replay exact (`harness.ts`):

- The page clock is paused at a fixed date and only moves in `Session.wait`.
- `Math.random` is seeded, and nothing in the app draws from it while rendering.
- `__CHESS_TEST__.engineDepth` swaps every engine for the backup engine at a
  fixed depth on the main thread (`src/engine/testEngine.ts`). It is never set
  in normal use.
- The test's own moves come from the saved Playbook, or from a depth-2 search.
