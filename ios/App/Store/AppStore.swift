import Book
import Foundation
import Model
import Observation
import UIKit

/// The app's state and the book, kept on the main actor and saved as JSON.
@MainActor @Observable
final class AppStore {
  private(set) var index: ReferenceIndex?
  private(set) var tree: OpeningTree?
  /// The opening picker's catalogue, built once from the tree.
  private(set) var catalog: PickerCatalog?
  var state = AppState()
  /// The favorite the last round landed on, so the next one is another.
  var lastFavorite: String?
  /// Any favorite resolved ahead of time, so Home's button and the round it starts agree.
  @ObservationIgnored private var ahead: (key: String, selection: Selection)?
  /// The save exists but could not be read (locked, say): saving now would replace it with a fresh state.
  @ObservationIgnored private var saveBlocked = false

  /// The profiles on this device and the one in use.
  private(set) var profiles = ProfileList()
  /// Changes whenever the state is swapped out (a switch or a reset), so screens start over.
  private(set) var session = UUID()

  /// This device's iCloud backup: its folder there and what it holds.
  private(set) var device = BackupDevice(folder: "", manifest: BackupManifest(device: ""))
  /// The last backup couldn't be written: iCloud is off or out of reach.
  private(set) var iCloudOff = false
  /// Other devices' backups, offered when a fresh install first opens.
  var restoreOffer: [DeviceBackup] = []
  @ObservationIgnored private let backup = ICloudBackup()
  @ObservationIgnored private var pendingBackup: Task<Void, Never>?
  /// The last iCloud write, so the next one waits its turn.
  @ObservationIgnored private var lastWrite: Task<Void, Never>?

  private let folder = URL.applicationSupportDirectory
  private var deviceFile: URL { folder.appending(path: "backup-device.json") }
  private var profilesFile: URL { folder.appending(path: "profiles.json") }
  private var file: URL { folder.appending(path: ProfileList.savePath(profiles.active)) }

  /// Load the book (and build the opening tree) off the main actor, then the saved state.
  func load() async {
    guard index == nil else { return }
    let built = await Task.detached(priority: .userInitiated) { () -> (ReferenceIndex, OpeningTree)? in
      guard let url = Bundle.main.url(forResource: "book", withExtension: "json"),
        let data = try? Data(contentsOf: url), let index = try? decodeBook(data)
      else { return nil }
      return (index, openingTree(index))
    }.value
    let fresh = !exists(profilesFile) && !exists(folder.appending(path: ProfileList.savePath(ProfileList.mainId)))
    loadDevice()
    if let data = try? Data(contentsOf: profilesFile), let list = try? JSONDecoder().decode(ProfileList.self, from: data) {
      profiles = list
    }
    readState()
    if let built {
      index = built.0
      tree = built.1
      catalog = pickerCatalog(built.1)
    }
    if fresh { Task { restoreOffer = await deviceBackups() ?? [] } }
  }

  private func exists(_ url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) }

  /// Read the active profile's save into `state`; none yet is a fresh start.
  private func readState() {
    state = AppState()
    saveBlocked = false
    lastFavorite = nil
    ahead = nil
    session = UUID()
    guard FileManager.default.fileExists(atPath: file.path(percentEncoded: false)) else { return }
    if let data = try? Data(contentsOf: file) {
      decode(data)
    } else {
      print("load failed: \(file.lastPathComponent) could not be read")
      saveBlocked = true
    }
  }

  private func decode(_ data: Data) {
    do {
      state = try JSONDecoder().decode(AppState.self, from: data)
    } catch {
      // The next save would overwrite it with a fresh state: keep the unreadable one beside it.
      print("load failed: \(error)")
      keepUnreadable(data)
      hold(profiles.active)
    }
  }

  /// A save this version cannot read, kept as `playbook-unreadable-<time>.json`.
  private func keepUnreadable(_ data: Data) {
    let stamp = Int(Date().timeIntervalSince1970)
    let copy = file.deletingLastPathComponent().appending(path: "playbook-unreadable-\(stamp).json")
    try? data.write(to: copy, options: .atomic)
  }

  private func saveProfiles() {
    do {
      try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
      try JSONEncoder().encode(profiles).write(to: profilesFile, options: .atomic)
    } catch {
      print("save failed: \(error)")
    }
  }

  /// Save this profile and open another.
  func switchProfile(_ id: String) {
    guard id != profiles.active else { return }
    save()
    backUpNow()
    profiles.activate(id)
    saveProfiles()
    readState()
  }

  /// A new profile, opened on a fresh start.
  func createProfile(_ name: String) {
    save()
    backUpNow()
    profiles.add(name, id: UUID().uuidString.lowercased())
    saveProfiles()
    readState()
  }

  func renameProfile(_ id: String, _ name: String) {
    profiles.rename(id, name)
    saveProfiles()
    send(profileId: nil, save: nil)
  }

  /// Delete a profile and its save. Deleting the one in use opens the next.
  func deleteProfile(_ id: String) {
    let wasActive = id == profiles.active
    if !wasActive { save() }
    guard profiles.remove(id) else { return }
    saveProfiles()
    removeSave(id)
    release(id)
    send(profileId: nil, save: nil)
    if wasActive { readState() }
  }

  /// Wipe the profile in use: a fresh start under the same name.
  func resetProfile() {
    release(profiles.active)
    removeSave(profiles.active)
    readState()
  }

  private func removeSave(_ id: String) {
    try? FileManager.default.removeItem(at: folder.appending(path: ProfileList.savePath(id)).deletingLastPathComponent())
  }

  func save() {
    guard !saveBlocked else { return }
    do {
      try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
      try JSONEncoder().encode(state).write(to: file, options: .atomic)
      scheduleBackup()
    } catch {
      print("save failed: \(error)")
    }
  }

  // MARK: iCloud backup

  /// This device's backup folder, made up on first launch.
  private func loadDevice() {
    if let data = try? Data(contentsOf: deviceFile), let saved = try? JSONDecoder().decode(BackupDevice.self, from: data) {
      device = saved
    } else {
      device = BackupDevice(folder: String(UUID().uuidString.prefix(8)), manifest: BackupManifest(device: UIDevice.current.model))
      saveDevice()
    }
  }

  private func saveDevice() {
    try? JSONEncoder().encode(device).write(to: deviceFile, options: .atomic)
  }

  /// Back up the profile in use a little after a change: every change saves, many a minute.
  private func scheduleBackup() {
    guard pendingBackup == nil else { return }
    pendingBackup = Task { [weak self] in
      try? await Task.sleep(for: .seconds(15))
      guard !Task.isCancelled else { return }
      self?.backUpNow()
    }
  }

  /// Back up the profile in use now: on leaving the app, and before opening another profile.
  /// A profile whose save failed to load stays held.
  func backUpNow() {
    pendingBackup?.cancel()
    pendingBackup = nil
    guard !saveBlocked, !backupHeld, let data = try? JSONEncoder().encode(state) else { return }
    send(profileId: profiles.active, save: data)
  }

  /// The profile in use isn't being backed up: its save failed to load, so it opened on a fresh start.
  var backupHeld: Bool { device.held.contains(profiles.active) }

  private func hold(_ id: String) {
    guard !device.held.contains(id) else { return }
    device.held.append(id)
    saveDevice()
  }

  private func release(_ id: String) {
    device.held.removeAll { $0 == id }
    saveDevice()
  }

  /// Write a save (or just the profile list after a rename or delete) to this device's backup,
  /// after any write still going.
  private func send(profileId: String?, save: Data?) {
    let now = Env.now()
    let day = backupDay(now)
    let old = device.manifest
    device.manifest = old.updated(profiles, saved: profileId, at: now, day: day)
    saveDevice()
    let drive = backup
    let folder = device.folder
    let manifest = device.manifest
    let gone = old.files.subtracting(manifest.files)
    let previous = lastWrite
    lastWrite = Task { [weak self] in
      await previous?.value
      let written = await drive.write(folder: folder, profileId: profileId, save: save, day: day, manifest: manifest, removing: gone)
      self?.iCloudOff = !written
    }
  }

  /// Backups to restore from, this device's own first; nil when iCloud is off.
  func deviceBackups() async -> [DeviceBackup]? {
    guard let urls = await findBackupManifests() else {
      iCloudOff = true
      return nil
    }
    return restoreChoices(await backup.manifests(urls), own: device.folder)
  }

  /// The day a restored file was filed under, when it isn't the copy asked for.
  private func olderDay(_ file: String, _ backed: BackedUpProfile, asked day: String?) -> String? {
    guard let first = backed.restoreFiles(from: day).first, file != first else { return nil }
    return backed.days.first { BackupManifest.snapshotFile(backed.id, $0) == file }
  }

  private func writeSave(_ data: Data, _ profileId: String) {
    let url = folder.appending(path: ProfileList.savePath(profileId))
    try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try? data.write(to: url, options: .atomic)
  }

  /// One profile from a backup, its latest save or `day`'s snapshot, falling back to older copies
  /// when that one can't be read. It replaces the profile with its id, or is added, and opens.
  func restore(_ backed: BackedUpProfile, from source: DeviceBackup, day: String?) async -> RestoreOutcome {
    guard let found = await backup.read(folder: source.folder, files: backed.restoreFiles(from: day)) else { return .failed }
    restoreOffer = []
    save()
    backUpNow()
    profiles.restore(backed)
    release(backed.id)
    writeSave(found.data, backed.id)
    saveProfiles()
    readState()
    send(profileId: backed.id, save: found.data)
    return .restored(olderDay: olderDay(found.file, backed, asked: day))
  }

  /// Every profile in a device's backup, each its newest readable copy, in place of this device's.
  func restoreAll(_ source: DeviceBackup) async -> RestoreOutcome {
    var saves: [(id: String, data: Data)] = []
    var fellBack: String?
    for profile in source.manifest.profiles {
      guard let found = await backup.read(folder: source.folder, files: profile.restoreFiles(from: nil)) else { continue }
      saves.append((profile.id, found.data))
      fellBack = fellBack ?? olderDay(found.file, profile, asked: nil)
    }
    guard !saves.isEmpty else { return .failed }
    restoreOffer = []
    let read = Set(saves.map(\.id))
    let restored = BackupManifest(device: source.manifest.device, profiles: source.manifest.profiles.filter { read.contains($0.id) })
    pendingBackup?.cancel()
    pendingBackup = nil
    for profile in profiles.profiles { removeSave(profile.id) }
    profiles = ProfileList(restoring: restored)
    device.held = []
    saveProfiles()
    for item in saves {
      writeSave(item.data, item.id)
      send(profileId: item.id, save: item.data)
    }
    readState()
    return .restored(olderDay: fellBack)
  }

  /// The next round's selection, without taking it: `peekRoundSelection`.
  func peekRoundSelection() -> Selection { peekRoundSelection(state) }

  /// The same, for a state not saved yet, such as onboarding's Playbook before it goes in:
  /// the answer is kept for the state it becomes.
  func peekRoundSelection(_ state: AppState) -> Selection {
    let selection = state.settings.selection
    guard isAnyFavorite(selection), let tree else { return selection }
    let key = "\(selection.color.rawValue) \(state.settings.favoriteOpenings.joined(separator: ",")) \(lastFavorite ?? "")"
    if ahead?.key != key { ahead = (key, roundSelection(state, tree, last: lastFavorite)) }
    return ahead!.selection
  }

  /// The next round's selection, taken: the one after lands on another favorite.
  func takeRoundSelection() -> Selection {
    let taken = peekRoundSelection()
    if isAnyFavorite(state.settings.selection) {
      if !taken.opening.isEmpty { lastFavorite = taken.opening }
      ahead = nil
    }
    return taken
  }

  /// Change the state and save it.
  func update(_ change: (inout AppState) -> Void) {
    change(&state)
    save()
  }
}
