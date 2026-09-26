# Claude notes for this repo

## Republish the artifact before handing the turn back

This project is published as a Claude Artifact, and the live page is the thing
people actually look at. A change that only exists in the repo is not done.

Batching is fine — republish once per batch of changes, not after every edit.
What matters is that the artifact is current at the end of every turn: never
finish a reply having changed app code, styles, or assets without republishing
first.

```bash
npm run build && npm run artifact
```

then publish `dist-artifact/index.html` with the Artifact tool, updating the
existing artifact rather than creating a new one:

- URL: https://claude.ai/code/artifact/8909c26a-7c93-47bc-9547-a426307eecd2
- Pass that `url` so the link stays the same, and pass the supporting files from
  `dist-artifact/files.json` (`root: "dist"`, `engine/stockfish.js` — the
  Stockfish worker needs a real URL and cannot be inlined).
- The favicon (♟️) and title stay as they are; do not pass a new one.
- Capabilities are `{db: {}, downloads: true}` (cloud sync and the JSON export).
  Omit `capabilities` on a normal republish so they carry forward; restate the
  full set if you ever change them.

Run `npm test` and `npm run typecheck` before publishing. Commit the change and
the republish together, so the repo and the live artifact never drift apart.
