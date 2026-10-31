# Chess Playbook for iOS

The native port of the web prototype. The plan is
[docs/native-port/plan.md](../docs/native-port/plan.md); what the app must do,
rule by rule, is [docs/spec/](../docs/spec/README.md).

## Layout

One Swift package, `ChessPlaybook`:

| Target | What | Prototype |
| --- | --- | --- |
| `Shared` | The few JavaScript behaviors ported code depends on: `Math.round`, `toFixed`, `localeCompare`, a stable sort, an insertion-ordered map | — |
| `ChessCore` | Board, legal moves, SAN, FEN: chess.js's rules and order, ported from it | `src/chess/core.ts`, chess.js |
| `Book` | The 2200+ book, decoded from `book.json`, and reading it: names, families | `book.ts`, `reference.ts` |
| `Model` | The opening tree and regions, the Playbook tree and its openings, extensions, the prepared floor, SRS cards, ratings, the selection, Any favorite and the picker catalogue; and for Autopilot: freshness, the line draw, recommend, where a run starts, Survival, missions, lenses and structures | `src/model/*` |

Phase 2 (native foundation) is these three layers. Phase 3 adds Autopilot:
the model above, then the run controller and the app.

## Parity tests

```bash
cd ios && swift test
```

`SpecTests` reads the golden cases in `spec/cases/functions/` and
`spec/constants.json` straight from the repo, so a prototype change that
regenerates them (`npm run spec:cases`) fails here until it is ported.
Each test names the case sets it ports; a set it names that the Swift code
does not answer the same way, or does not port, is a failure.

Ported so far:

- `chess.json`: all (seeded random games, SAN parsing)
- `draw.json`, `recommend.json`, `survival.json`, `missions.json`, `lenses.json`: all
- `autopilot.json`: all
- `naming.json`: all
- `srs.json`: all
- `ratings.json`: all
- `playbook.json`: all
- `picker.json`: `picker.*`
- `growth.json`: `selection.*`, `anyFavorite.*`
- `home.json`: `scoring.*`
- `spec/constants.json`: every constant of the ported modules

`PickerData.swift` and `StructureTemplates.swift` are written out from
`spec/constants.json` (and, for the structures' tests, `structures.ts`) by a
one-off script; the constants tests keep them equal to the prototype.

`ChessCoreTests` adds perft counts on the standard positions.

## Porting notes

- Sorts use `jsSorted`: JavaScript's sort is stable and Swift's is not, and
  ties are broken by original order throughout the model.
- Name orderings use `JS.localeCompare` (`en_US`), as the prototype's
  `localeCompare` does.
- Day keys (`dayKey`) are local calendar days, like the prototype's.
- `Env.now` and `Env.random` are the injected clock and chance; the seeded
  generator is `mulberry32`, bit for bit.
- Not yet ported: the famous games the explorer pins to positions
  (`topGames`), left for the screen that shows them.
