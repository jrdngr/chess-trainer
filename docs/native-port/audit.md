# Phase 0 audit

Done 2026-10-31 on main. This is what the port leaves out, and where the
prototype's written record disagrees with its code. The decisions it rests
on are in [plan.md](plan.md#decisions).

## Not ported, deleted from the prototype in phase 1

Found by tracing every top-level declaration reachable from `src/main.tsx`
(TypeScript compiler API, tests excluded). About 1,200 lines are unreachable:

| Where | What |
| --- | --- |
| `model/openingRun.ts` | The old Run mode: hints, new-moves budgets, steer labels, `classify`, `play`, `takeHint`, grades, `leavePrep`, `finishPrep`, `keepPlaying`, edge options, `revealText`, `lineName`, run records, `lineToKeep` (~245 lines). Survival keeps `prepIndex`, `regionSource`, `beginRun`, `opponentReply`, `BOOK_SHARE`, `BLUNDER_LIMIT` and `judgeByEval`. |
| `model/seed/repertoires.ts`, `store/seed.ts` | Sample repertoires and the seeder that built them (~420 lines). Onboarding replaced both. |
| `model/gaps.ts` | The old gap finder (86 lines). |
| `model/repair.ts` | `isRepaired`, `lineFor`, `fixCandidates`, `matchesPosition`, `openingMismatch`. `buildRepairs` stays, since it feeds the evidence used for steering. |
| `model/picker.ts` | `groupOf` and the Popular / Sharpest / … sort, cut from Browse. |
| `model/growth.ts` | `findCoverage`, `thinness` and their weights. |
| `model/growOffer.ts` | `isStubFinish`, `plyLabel`, `yourLastMove`. |
| `model/reference.ts` | `openingById`, `deepestNameForColor`, `specificNameForColor`. |
| Others | `tidyFinds`, `gradePreview`, `ratingSwing`, `tierColor`, `hasLine`, `lineText`, `countNodes`, `insideRegion`, `openingsAcross`, `picksFrom`, `starterSet`, `setSeed`, `resultLabel`, `clearEngineReplies`, `eventPlace`, `findingToLine`, `allLines` (PGN), `plyOf`, `isPromotion`, `isLightSquare`, `PIECE_NAMES`, mistakes' `sourceLabel`, `addedByYou`, `openingOf`. |

The trace also flagged the backup engine's piece-square tables. That's a false
positive: they are used by a loop at module level. They stay.

Also not ported, by decision:

- **Mode Testing**: the toggle, `TestVariant`, `testCycle`, `forcedStart`,
  `pickRound`'s test path, `tookTest`, `AutopilotPrefs.modeTesting`.
- **Old-save handling**, since the native app starts fresh:
  `normalizeSources` (the old `reference` source migration), the legacy
  mission `goal` field, `SurvivalScore.history` seeding from `recent`, the
  cards' date fallback for unstamped `testedRound`, and the `run` ("Autopilot
  (old)") and `repair` activity modes in Stats. `normalizeScore`,
  `normalizeSurvival`, `normalizeEvents` and `normalizeRecord` only exist to
  read older saves. The native store gets its own versioning from day one.

## Reachable but never shown

- **The "Prep complete" label.** The moment prep runs out, the same effect
  sets either the book phase or Out of book, so the prompt goes straight to
  "In the book" or "Out of book". The label's copy and color exist, but no
  player state shows them. The spec documents the three labels that do show.
- **`AUTO_DRILL`** is only read for `newPerSession` (8), which feeds the
  recommendation's review need. The rest of it served Autopilot's Drill
  rounds, which were removed on 10-23. The spec keeps the one number.
- **Growth's engine replies past the book** are live only under Growth's
  "Past the book" setting (off by default, and off in Autopilot's batch). They
  get ported with full Growth in phase 5.

## Where the written record has drifted

The code was checked against the latest decision on each point (survival
feedback, glow, combo, moments, missions, ratings, tiers, SRS, starts, book
phase, prepared floor, Any favorite, end screen, Grow this line, autopilot
settings). **No rule checked disagrees with the code.** The drift is all in
the written record, which is why the spec is built from the code:

- **README.md** describes an Autopilot that no longer exists: a ten-second
  clock, focuses, checkpoints, "Next run". It also still describes Repair as a
  mode. Phase 1 replaces those sections with links to `docs/spec/`.
- **Decision notes** are a history, so earlier ones are overridden by later
  ones. Examples: Cold Start every 4th run (now 3rd, by need), the Survival
  header's rating bar (moved to the end screen on 10-28), Survival after every
  Drill round (Autopilot has no Drill rounds now), "Keep this line" (removed).
  Each spec rule cites the latest note it follows.
- **One behavior worth confirming during the spec:** Survival's end screen
  shows Analyze only after a blunder or End run, not after mate or a draw.
  That matches the 09-28 decision, but it's the kind of detail the spec will
  ask about again rather than assume.

Every remaining rule is checked against the code as its spec entry is written
in phase 1. Any mismatch goes to the owner and is never silently resolved.
