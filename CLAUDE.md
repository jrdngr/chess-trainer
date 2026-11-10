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
cd ios && ./scripts/fetch-caissa-net.sh && swift test
```

`scripts/fetch-caissa-net.sh` puts Caissa's network (76 MB, not in git) in
`Sources/Engine/CaissaNet/`. Without it the app builds but offers only the
Basic engine, and the Caissa tests are skipped. Xcode Cloud runs it after the
clone (`ios/ci_scripts/ci_post_clone.sh`).

In a Linux cloud container, use Docker (download.swift.org may be blocked;
Docker Hub works):

```bash
pgrep dockerd >/dev/null || (nohup dockerd >/tmp/dockerd.log 2>&1 &); sleep 5
cd ios && ./scripts/fetch-caissa-net.sh
docker run --rm -v "$PWD":/src -w /src swift:6.4-noble swift test
rm -rf .build  # root-owned build output from the container
```

Linux builds the package only (ChessCore, Book, Model, Engine, Caissa and their
tests), not the SwiftUI app in `ios/App`. Keep package code portable: guard
Apple-only APIs with `#if canImport(...)`, and import `FoundationNetworking`
where URLSession is used. Xcode Cloud builds the whole app on every push to
`main` and then runs the tests (`ios/ci_scripts/ci_post_xcodebuild.sh`).

`ios/Tests/SpecTests/Golden/` holds recorded answers the model must keep
giving. When a change to the app's behavior is intended, update the affected
cases in the same commit and say why in the message.

## Autopilot's intent

Before changing Autopilot, read [docs/autopilot.md](docs/autopilot.md). It
says what Autopilot is for, and each change should pass its tests.
