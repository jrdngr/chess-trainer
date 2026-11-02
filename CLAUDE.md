# Claude notes for this repo

The product is the native iOS app in `ios/`. The web prototype and the spec
generated from it were removed on 2026-11-02; their final state is on the
`archive/web-prototype` branch, for reference only.

## Branches

- Work on `dev` and push there.
- Merge `dev` into `main` only when the owner says the next release is
  settled. Every push to `main` starts an Xcode Cloud build.

## Checks

Run the Swift tests before pushing; GitHub Actions runs them on every push to
`dev` and `main`, and builds the app.

```bash
cd ios && swift test
```

`ios/Tests/SpecTests/Golden/` holds recorded answers the model must keep
giving. When a change to the app's behavior is intended, update the affected
cases in the same commit and say why in the message.

## Autopilot's intent

Before changing Autopilot, read [docs/autopilot.md](docs/autopilot.md). It
says what Autopilot is for, and each change should pass its tests.
