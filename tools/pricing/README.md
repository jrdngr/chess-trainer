# Pawn pricing

The numbers in [docs/monetization.md](../../docs/monetization.md) come from here.

The bot plays runs on the player's side headless (`playbook measure`), and each run is
saved as counts: prep, growth and other moves, misses, how it ended, and how many times
each pawn event paid. Time and pawn values are applied afterwards, in the calculator, so a
value or price change needs no new games.

## Files

- `runs.jsonl`: the measured runs, one per line (2,340 runs, measured 2026-11-18, under
  the pawn rules in docs/monetization.md).
- `jobs.txt`: the sweep, one `playbook measure` call per line: the seed, then its options.
- `pawn-rates.template.html`: the calculator. Its inputs (pawns per event, distance
  markers, Endgames bounties, streak, seconds, prices) default to the values in the doc.
  Its Targets table checks every earning target.
- `build.py`: puts `runs.jsonl` into the template as `pawn-rates.html` (not committed).
- `sweep.sh`: plays every job again and rebuilds.

## Time assumptions

Seconds, at the owner's pace, measured from a 16-run session on 2026-11-17:

| | Seconds |
| --- | --- |
| Prep move | 2 |
| Growth pick | 2 |
| Move past prep | 3 |
| Move past prep, new player | 6 |
| Endgames move | 3 |
| Per run (deal, end screen) | 4 |
| Per Middlegame run (handoff) | 12 |

The baseline (1x) is prep-only drilling, all levels and both sides, at the owner's pace.
Full runs and Middlegame are checked at the new player's pace past prep.

## Use

```bash
python3 tools/pricing/build.py        # rebuild pawn-rates.html from runs.jsonl, then open it
tools/pricing/sweep.sh                # play the sweep again (slow), then rebuild
```

Rerun the sweep after any change to how pawns are earned, since the runs record what
paid under the rules they were played with.
