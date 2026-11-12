# Chess Playbook for iOS

## Layout

`App/` is the SwiftUI app; `project.yml` generates its Xcode project with
XcodeGen. `Resources/book.json` is the opening book it ships. The logic is one
Swift package, `ChessPlaybook`:

| Target | What |
| --- | --- |
| `Shared` | Number formatting, string ordering, a stable sort and an insertion-ordered map, matched to the golden cases' JavaScript origin |
| `ChessCore` | Board, legal moves, SAN, FEN |
| `Book` | The 2200+ book, decoded from `book.json`, and reading it: names, families |
| `Model` | The opening tree and regions, the Playbook tree and its openings, extensions, the prepared floor, SRS cards, ratings, the selection, Any favorite, the picker catalogue and its browse lists; Autopilot, Survival, Drill and Growth as pure controllers; missions, lenses and structures; import |
| `Engine` | The engine (bitboard alpha-beta search), the judge, and the Pawns lens's best breaks; the human-like levels are in `Model/Strength.swift` |
| `Game` | The app without its screens: the store and its saves, Play's rounds (`PlaySession`, `RunModel`), Growth sittings, Middlegame and Endgames, all on injected time, engines and storage (`GameServices`). `HeadlessApp` drives it from code; `ScriptedEngine` is a fast, fixed engine for it |
| `PlaybookCLI` | `playbook`, the app on the command line |

## Tests

```bash
cd ios && swift test
```

- `ChessCoreTests`: perft counts on the standard positions.
- `EngineTests`: Caissa, the judge and plan checks. `ENGINE_BENCH=1` adds the judge and level benchmarks.
- `FlowTests`: user flows played start to finish on `HeadlessApp`: onboarding and the tutorial, Drill and Freeform rounds, misses and blunders, growing, Endgames, Middlegame, saves and profiles.
- `SpecTests`: the model against the golden cases in `Tests/SpecTests/Golden/`
  (`cases/functions/*.json`, `cases/scenarios/*.json`, `constants.json`).
  They were recorded from the web prototype and are now plain fixtures: when a
  behavior change is intended, edit the affected cases with it.

`PickerData.swift`, `StructureTemplates.swift` and `StarterSets.swift` hold
data that the constants tests compare with `Golden/constants.json`.

## Playing without the screens

The views in `App/` only draw and forward taps; everything a tap sets off
runs in `Game`, which builds on Linux. `HeadlessApp` plays it from code:

```swift
try await HeadlessApp.run(book: bookURL, seed: 1) { app in
  try app.skipTutorial(starter: "classical")
  try app.select(side: .w, start: .drill)
  await app.openPlay()
  try await app.move("Nf3")
  print(app.report())
}
```

Every action settles before it returns: the opponent has replied, and the
popups and callouts that came and went are in `app.signals`. Time is a
`VirtualClock` that only moves while the game waits, and `run` pins `Env`'s
clock and chance, so a seed replays the same game. Engines default to
`ScriptedEngine`; pass `engine: { makeEngine() }` for Caissa.

The same thing on the command line, with Caissa:

```bash
cd ios && swift run playbook            # --engine scripted, --seed N, --save DIR
```

It reads one command per line (`help` lists them) and prints the screen as
text after each, so an agent can play a whole game through stdin.

## Notes

- Sorts use `jsSorted`, which is stable; ties are broken by original order throughout the model.
- Name orderings use `JS.localeCompare` (`en_US`).
- Day keys (`dayKey`) are local calendar days.
- `Env.now` and `Env.random` are the injected clock and chance; the seeded
  generator is `mulberry32`.
- Not built yet: the famous games the explorer pins to positions (`topGames`).

## App icon

`App/Assets.xcassets/AppIcon.appiconset/AppIcon.png` is a single 1024px
opaque PNG; iOS masks the corners and scales it down. Its source is
`Design/app-icon.svg` (three Leitner boxes in indigo shades, the knight card
leaving the middle box for the lightest). Re-render the PNG from the SVG after editing it.

## Builds and versions

- Xcode Cloud archives every push to `main` for TestFlight, and builds every push to `dev` without publishing; after a `dev` build, `ci_scripts/ci_post_xcodebuild.sh` runs `swift test`. `ci_scripts/ci_post_clone.sh` installs XcodeGen and generates the project, since `ChessPlaybook.xcodeproj` is not checked in.
- The marketing version is `MARKETING_VERSION` in `project.yml`. To bump it, edit it there and regenerate.
- Xcode Cloud sets the build number on every archive. Local builds stay at `1`. They are only for installing on a device, never for uploading.
