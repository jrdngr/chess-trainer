import Foundation
import Game
import Model
import Testing

/// An iCloud drive in memory: each folder's files by name.
private actor MemoryDrive: BackupDrive {
  var folders: [String: [String: Data]] = [:]

  func write(folder: String, profileId: String?, save: Data?, snapshot: Bool, day: String, manifest: BackupManifest, removing gone: Set<String>) -> Bool {
    if let profileId, let save {
      folders[folder, default: [:]][BackupManifest.saveFile(profileId)] = save
      if snapshot { folders[folder, default: [:]][BackupManifest.snapshotFile(profileId, day)] = save }
    }
    folders[folder, default: [:]][BackupManifest.file] = try? JSONEncoder().encode(manifest)
    for name in gone { folders[folder]?[name] = nil }
    return true
  }

  func manifests(_ urls: [URL]) -> [DeviceBackup] { [] }

  func read(folder: String, files: [String]) -> (file: String, data: Data)? {
    for file in files {
      if let data = folders[folder]?[file], isCurrentSave(data) { return (file, data) }
    }
    return nil
  }

  func findManifests() -> [URL]? { [] }

  func put(_ folder: String, _ file: String, _ data: Data) { folders[folder, default: [:]][file] = data }
  func file(_ folder: String, _ file: String) -> Data? { folders[folder]?[file] }
  func all() -> [String: [String: Data]] { folders }
}

private func pawns(_ data: Data?) -> Int? { data.flatMap { try? decodeSave($0).pawns } }

private func saveWith(pawns: Int) throws -> Data {
  var state = AppState()
  state.pawns = pawns
  return try JSONEncoder().encode(state)
}

/// Leaving the app while it is still loading backs up nothing: the blank placeholder state
/// never replaces a backup, and the device keeps its backup folder.
@MainActor @Test func nothingIsBackedUpBeforeTheSavesAreRead() async throws {
  let storage = MemoryStorage()
  try storage.write(ProfileList.savePath(ProfileList.mainId), try saveWith(pawns: 700))
  let drive = MemoryDrive()
  let store = AppStore(storage: storage, backup: drive)
  store.backUpNow()
  await store.backupsWritten()
  #expect(await drive.all().isEmpty)
  #expect(!storage.exists("backup-device.json"))

  await store.load(book: nil)
  #expect(store.state.pawns == 700)
  store.backUpNow()
  await store.backupsWritten()
  #expect(pawns(await drive.file(store.device.folder, "main.json")) == 700)
}

/// A restore over the profile in use keeps today's snapshot as it was before the restore, for
/// the rest of the day, so it can be undone. The latest save is the restored one.
@MainActor @Test func aRestoreKeepsTheCopyItReplaced() async throws {
  let drive = MemoryDrive()
  let store = AppStore(storage: MemoryStorage(), backup: drive)
  await store.load(book: nil)
  store.update { $0.pawns = 500 }
  store.backUpNow()

  let other = "other"
  let backed = BackedUpProfile(id: ProfileList.mainId, name: "Main", savedAt: 1, days: [])
  await drive.put(other, "main.json", try saveWith(pawns: 100))
  let source = DeviceBackup(folder: other, manifest: BackupManifest(device: "iPad", profiles: [backed]))
  #expect(await store.restore(backed, from: source, day: nil) == .restored(olderDay: nil))
  #expect(store.state.pawns == 100)

  store.update { $0.pawns = 150 }
  store.backUpNow()
  await store.backupsWritten()
  let own = store.device.folder
  let today = BackupManifest.snapshotFile(ProfileList.mainId, backupDay(Env.now()))
  #expect(pawns(await drive.file(own, "main.json")) == 150)
  #expect(pawns(await drive.file(own, today)) == 500, "today's snapshot is the copy from before the restore")
}

/// A backup from an older version can't be restored: it would only open as a fresh start,
/// so the restore fails and the profile stays as it is.
@MainActor @Test func anOlderBackupIsNotRestored() async throws {
  let drive = MemoryDrive()
  let store = AppStore(storage: MemoryStorage(), backup: drive)
  await store.load(book: nil)
  store.update { $0.pawns = 500 }
  var old = AppState()
  old.pawns = 100
  old.version = SAVE_VERSION - 1
  let backed = BackedUpProfile(id: ProfileList.mainId, name: "Main", savedAt: 1, days: [])
  await drive.put("other", "main.json", try JSONEncoder().encode(old))
  let source = DeviceBackup(folder: "other", manifest: BackupManifest(device: "iPad", profiles: [backed]))
  #expect(await store.restore(backed, from: source, day: nil) == .failed)
  #expect(store.state.pawns == 500)
}
