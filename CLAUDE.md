# Claude notes for this repo

The product is the native iOS app in `ios/`. The web prototype and the spec
generated from it were removed on 2026-11-02; their final state is on the
`archive/web-prototype` branch, for reference only.

## Branches

- Commit straight to `dev` once the tests below pass. No fix branches. Hold
  the commits locally and push to `dev` only when the owner says to; changes
  are collected into one push.
- Merge `dev` into `main` only when the owner says the next release is
  settled. Every push to `main` starts an Xcode Cloud build.

## Checks

Run the Swift tests before pushing. On a Mac:

```bash
cd ios && swift test
```

In a Linux cloud container, use Docker (download.swift.org may be blocked;
Docker Hub works):

```bash
pgrep dockerd >/dev/null || (nohup dockerd >/tmp/dockerd.log 2>&1 &); sleep 5
cd ios && docker run --rm -v "$PWD":/src -w /src swift:6.4-noble swift test
rm -rf .build  # root-owned build output from the container
```

Linux builds the package only (ChessCore, Book, Model, Engine and their
tests), not the SwiftUI app in `ios/App`. Keep package code portable: guard
Apple-only APIs with `#if canImport(...)`, and import `FoundationNetworking`
where URLSession is used. Xcode Cloud's dev workflow builds the whole app on
every push to `dev` and then runs the tests
(`ios/ci_scripts/ci_post_xcodebuild.sh`); it publishes nothing from `dev`.

`ios/Tests/SpecTests/Golden/` holds recorded answers the model must keep
giving. When a change to the app's behavior is intended, update the affected
cases in the same commit and say why in the message.

## Autopilot's intent

Before changing Autopilot, read [docs/autopilot.md](docs/autopilot.md). It
says what Autopilot is for, and each change should pass its tests.
