import Foundation
import Model
import Testing

private func profiles(_ pairs: [(String, String)]) -> ProfileList {
  var list = ProfileList()
  for (id, name) in pairs { list.add(name, id: id) }
  return list
}

/// Saving one profile stamps only it; the list's order, names and deletions carry over,
/// and a profile with no save yet stays out.
@Test func manifestFollowsTheList() {
  var list = profiles([("b", "Blitz"), ("c", "Club")])
  var manifest = BackupManifest(device: "iPhone")
    .updated(list, saved: "main", at: 100, day: "2026-11-01")
    .updated(list, saved: "b", at: 200, day: "2026-11-02")
  #expect(manifest.profiles.map(\.id) == ["main", "b"])

  list.rename("main", "Long term")
  _ = list.remove("b")
  manifest = manifest.updated(list, saved: "c", at: 300, day: "2026-11-03")
  #expect(manifest.profiles == [
    BackedUpProfile(id: "main", name: "Long term", savedAt: 100, days: ["2026-11-01"]),
    BackedUpProfile(id: "c", name: "Club", savedAt: 300, days: ["2026-11-03"]),
  ])
  #expect(manifest.savedAt == 300)
  #expect(manifest.device == "iPhone")
}

/// Snapshots: one per day played, newest first, the last 7 days played kept. The files no
/// longer listed (dropped days, deleted profiles) are what the backup removes.
@Test func snapshotsKeepTheLastSevenDaysPlayed() {
  var list = ProfileList()
  var manifest = BackupManifest(device: "iPhone")
  for day in 1...9 {
    manifest = manifest.updated(list, saved: "main", at: Double(day), day: "2026-11-0\(day)")
    manifest = manifest.updated(list, saved: "main", at: Double(day) + 0.5, day: "2026-11-0\(day)")
  }
  let main = manifest.profiles[0]
  #expect(main.days == ["2026-11-09", "2026-11-08", "2026-11-07", "2026-11-06", "2026-11-05", "2026-11-04", "2026-11-03"])
  #expect(main.olderDays.first == "2026-11-08")
  #expect(manifest.files.count == 8)
  #expect(manifest.files.contains("main.json") && manifest.files.contains("main-2026-11-03.json"))

  list.add("B", id: "b")
  let withB = manifest.updated(list, saved: "b", at: 10, day: "2026-11-10")
  _ = list.remove("b")
  let gone = withB.files.subtracting(withB.updated(list, saved: nil, at: 11, day: "2026-11-10").files)
  #expect(gone == ["b.json", "b-2026-11-10.json"])
}

/// Restoring tries the chosen copy, then every older one.
@Test func restoreFallsBackToOlderCopies() {
  let profile = BackedUpProfile(id: "main", name: "Main", savedAt: 1, days: ["2026-11-05", "2026-11-04", "2026-11-02"])
  #expect(profile.restoreFiles(from: nil) == ["main.json", "main-2026-11-05.json", "main-2026-11-04.json", "main-2026-11-02.json"])
  #expect(profile.restoreFiles(from: "2026-11-04") == ["main-2026-11-04.json", "main-2026-11-02.json"])
  #expect(profile.restoreFiles(from: "2026-10-01").isEmpty)
}

/// A fresh install restoring a device takes its whole list, on the first profile.
@Test func restoringAWholeDevice() {
  let backup = BackupManifest(device: "iPad", profiles: [
    BackedUpProfile(id: "x", name: "Openings", savedAt: 5),
    BackedUpProfile(id: "main", name: "Main", savedAt: 9),
  ])
  let list = ProfileList(restoring: backup)
  #expect(list.profiles == [Profile(id: "x", name: "Openings"), Profile(id: "main", name: "Main")])
  #expect(list.active == "x")
  #expect(ProfileList(restoring: BackupManifest(device: "iPad")) == ProfileList())
}

/// Restoring one profile replaces the one with its id (taking the backup's name) or adds it,
/// and opens it either way.
@Test func restoringOneProfile() {
  var list = profiles([("b", "Blitz")])
  list.rename("main", "Renamed here")
  let replaced = list.restore(BackedUpProfile(id: "main", name: "Main", savedAt: 1))
  #expect(replaced)
  #expect(list.active == "main")
  #expect(list.profiles.map(\.name) == ["Main", "Blitz"])

  let added = list.restore(BackedUpProfile(id: "old", name: "Old phone", savedAt: 1))
  #expect(!added)
  #expect(list.active == "old")
  #expect(list.profiles.map(\.id) == ["main", "b", "old"])
}

/// Empty backups aren't offered; this device's own comes first, then the newest.
@Test func restoreChoicesOwnFirstSkipEmpty() {
  func device(_ folder: String, _ times: [Double]) -> DeviceBackup {
    DeviceBackup(folder: folder, manifest: BackupManifest(device: "iPhone", profiles: times.enumerated().map {
      BackedUpProfile(id: "p\($0.offset)", name: "P", savedAt: $0.element)
    }))
  }
  let choices = restoreChoices([device("old", [10, 50]), device("mine", [99]), device("empty", []), device("new", [60])], own: "mine")
  #expect(choices.map(\.folder) == ["mine", "new", "old"])
}
