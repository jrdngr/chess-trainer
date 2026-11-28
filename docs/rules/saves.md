# Saves from older versions, and sealed backups

What happens to a save written by an older version, and how a backup is
kept from being edited. Code: `SaveVersion.swift`, `SaveSeal.swift`. Tests: the `docs/rules/saves.md` suite in
`Tests/SpecTests/Rules/SavesRules.swift`.

1. **Every save has a version.** A new save starts at the current one (7).
   A save written before versions existed counts as 0.
2. **An older save is wiped.** A save from before the current version loads
   as a fresh start: Welcome, no Playbook, no pawns. Nothing in it is
   brought up to date, and the fresh profile replaces it on the next save.
3. **An older backup isn't restored.** Restoring from iCloud skips a copy
   from an older version, since it would only open as a fresh start, and
   tries the next older copy. When none is current, the restore fails and
   the profile stays as it is.
4. **A backup is sealed.** Each save written to iCloud carries an
   HMAC-SHA256 of its bytes under a key built into the app, and the
   number of that key. A restore skips a copy whose seal doesn't match,
   that has none, or whose key the app doesn't have, the same way it
   skips an older one. Old keys stay in the app so their copies still
   restore; the next backup reseals with the newest key. The iCloud folder isn't shown in the Files app.
