# Data

What is kept, where, and what the event log records. The rules are in
`src/store/useStore.ts`, `src/store/cloud.ts`, `src/store/db.ts`,
`src/model/events.ts` and the Playbook tab's Export.

The native app starts fresh and does not read web saves (plan, decision 3),
so the storage format here is not a contract. What carries over is what is
kept, how two copies are reconciled, and what the log says.

## What is kept

**DATA-1** · port
One saved state holds the Playbook (both sides' trees and their order), the
cards and line cards, the review log, settings, imported and Play games,
Survival's state, the mistakes log, the score (ratings and per-day tallies),
and the event log. A new install starts with nothing in the Playbook. Every
change is saved locally a moment after it is made.
Source: `useStore.persistedFrom`, `useStore.emptyPersisted`, `db.saveState`
Cases: `store.resetProgress`, `onboarding.onboarded`

**DATA-2** · port
Settings has two resets, each asking for a second tap. Reset progress clears
the cards, line cards and review log, and keeps the Playbook, the ratings,
the mistakes log and the event log. Reset everything starts over empty.
Source: `SettingsSheet`, `useStore.resetProgress`, `useStore.resetAll`
Cases: `store.resetProgress`

## Sync

**DATA-3** · port
With Sync on (the default) the whole state is one account copy, written about
4 seconds after you stop changing things, and never before the account copy
has been read at startup. Only Play games travel; imported games stay on the
device that imported them.
Source: `useStore.pushCloud`, `useStore.syncableFrom`, `cloud.writeCloud`
Cases: `play.mergeGames`, `cloud.describeStatus`

**DATA-4** · port
At startup, and on Sync now, the newer copy wins whole (last write wins, by
when it was last changed; a copy from another schema is ignored). Sync now
also merges both copies' Play games by id, newest first, so a game played on
either device is kept.
Source: `useStore.init`, `useStore.syncNow`, `play.mergeGames`
Cases: `play.mergeGames`

**DATA-5** · port
The Sync row says where sync stands: not available on this device, Syncing…,
Ready, Synced just now / N min / N h / N d ago, too large (the account copy
holds 240 KiB after compression), or the error.
Source: `cloud.describeStatus`
Cases: `cloud.describeStatus`

## Export

**DATA-6** · port
The Playbook tab's Export as JSON saves both sides' trees as stored and the
event log, in one file named `repertoire-<date>.json`, tagged
`chess-trainer-repertoire` version 1. Where saving files is not possible it
says so.
Source: `RepertoireScreen.exportReps`, `saveFile`
Cases: `events.log`

## The event log

**DATA-7** · port
Every change to the Playbook is logged with when and where in the app it
happened: lines added (with how many moves were new; nothing new logs
nothing), deletes of a move, a line, an opening or a whole side (with the
lines they took and how many moves), undos, preferred moves, notes, reorders,
and Tidy's switch, keep and remove with their undos. Growth logs its start,
each offer (what was offered and where it came from), each pick, undo, and
going on past the book.
Source: `events.AppEvent`, `useStore` (each action), `growth/Lobby`, `GrowthScreen`
Cases: `events.log`

**DATA-8** · port
A delete lists every line of the old tree that lost a move, whole, at most 20
of them, and counts every move that went.
Source: `events.removedBetween`
Cases: `events.removedBetween`, `const:REMOVED_CAP`

**DATA-9** · port
The log keeps the newest 1000 events, synced and exported with everything
else; a saved log of any other shape reads as empty.
Source: `events.appendEvent`, `events.normalizeEvents`
Cases: `events.appendEvent`, `events.normalizeEvents`, `const:EVENT_CAP`

## Settled

- **Reset progress** ported as the code does it: it clears the schedule and keeps ratings, mistakes, tallies and the event log.
- **Startup sync** ported as the code does it: the newer copy wins whole at startup, and only Sync now merges Play games.

The owner ruled on 10-31 that the code is the truth: these stay until the owner asks for a change.
