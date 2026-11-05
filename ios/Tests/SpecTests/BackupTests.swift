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
    .updated(list, saved: "main", at: 100)
    .updated(list, saved: "b", at: 200)
  #expect(manifest.profiles.map(\.id) == ["main", "b"])

  list.rename("main", "Long term")
  _ = list.remove("b")
  manifest = manifest.updated(list, saved: "c", at: 300)
  #expect(manifest.profiles == [
    BackedUpProfile(id: "main", name: "Long term", savedAt: 100),
    BackedUpProfile(id: "c", name: "Club", savedAt: 300),
  ])
  #expect(manifest.savedAt == 300)
  #expect(manifest.device == "iPhone")
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

/// This device's own folder and empty backups aren't offered; the newest comes first.
@Test func restoreChoicesSkipOwnAndEmpty() {
  func device(_ folder: String, _ times: [Double]) -> DeviceBackup {
    DeviceBackup(folder: folder, manifest: BackupManifest(device: "iPhone", profiles: times.enumerated().map {
      BackedUpProfile(id: "p\($0.offset)", name: "P", savedAt: $0.element)
    }))
  }
  let choices = restoreChoices([device("old", [10, 50]), device("mine", [99]), device("empty", []), device("new", [60])], own: "mine")
  #expect(choices.map(\.folder) == ["new", "old"])
}
