# Claude notes for this repo

The product is the native iOS app in `ios/`. The web prototype and the spec
generated from it were removed on 2026-11-02; their final state is on the
`archive/web-prototype` branch, for reference only.

## Branches

- Commit straight to `main` once the tests below pass. No fix branches. Hold
  the commits locally and push to `main` only when the owner says to; changes
  are collected into one push. Every push to `main` starts an Xcode Cloud
  build with the same checks as `dev`.
- `dev` is no longer pushed to.

## Checks

Run the Swift tests before pushing. On a Mac:

```bash
cd ios && swift test
```

In a Linux cloud container, use Docker (download.swift.org may be blocked;
Docker Hub works):

```bash
pgrep dockerd >/dev/null || (nohup dockerd >/tmp/dockerd.log 2>&1 &); sleep 5
cd ios
docker run --rm -v "$PWD":/src -w /src swift:6.4-noble swift test
rm -rf .build  # root-owned build output from the container
```

Linux builds the package only (ChessCore, Book, Model, Engine, Caissa, Game,
the `playbook` CLI and their tests), not the SwiftUI app in `ios/App`. Keep
logic out of `ios/App`: anything a tap sets off belongs in `Game`, so it builds
and is tested on Linux. Keep package code portable: guard
Apple-only APIs with `#if canImport(...)`, and import `FoundationNetworking`
where URLSession is used. Xcode Cloud builds the whole app on every push to
`main` and then runs the tests (`ios/ci_scripts/ci_post_xcodebuild.sh`).

To try a change the way a player would, play it headless: `HeadlessApp` in
the `Game` target drives every mode from code, and `swift run playbook` (run
through Docker on Linux) plays the app from stdin. New user flows get a test
in `ios/Tests/FlowTests/`. See "Playing without the screens" in
`ios/README.md`.

`ios/Tests/SpecTests/Golden/` holds recorded answers the model must keep
giving. When a change to the app's behavior is intended, update the affected
cases in the same commit and say why in the message.

## Play's intent and the gameplay rules

Before changing Play, read [docs/gameplay.md](docs/gameplay.md). It says
what Play is for, and each change should pass its tests.

[docs/rules/](docs/rules/README.md) says what the gameplay code does, one
topic per file, each rule backed by a test in the suite named after its file
(`ios/Tests/SpecTests/Rules/`). A change to gameplay updates its rule and test
in the same commit.
