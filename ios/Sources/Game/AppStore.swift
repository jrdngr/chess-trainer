import Book
import Engine
import Foundation
import Model
import Observation

/// The app's state and the book, kept on the main actor and saved as JSON.
@MainActor @Observable
public final class AppStore {
  public private(set) var index: ReferenceIndex?
  public private(set) var tree: OpeningTree?
  /// The opening picker's catalogue, built once from the tree.
  public private(set) var catalog: PickerCatalog?
  public var state = AppState()
  /// Play's recent rounds this session, kept across trips Home so the next round's start follows them.
  public var autoHistory = AutoHistory()
  /// The save exists but could not be read (locked, say): saving now would replace it with a fresh state.
  @ObservationIgnored private var saveBlocked = false

  /// The profiles on this device and the one in use.
  public private(set) var profiles = ProfileList()
  /// Changes whenever the state is swapped out (a switch or a reset), so screens start over.
  public private(set) var session = UUID()
  /// Settings was open when the session changed under it: Home opens it again.
  @ObservationIgnored private var settingsHeld = false

  /// This device's iCloud backup: its folder there and what it holds.
  public private(set) var device = BackupDevice(folder: "", manifest: BackupManifest(device: ""))
  /// The last backup couldn't be written: iCloud is off or out of reach.
  public private(set) var iCloudOff = false
  /// Other devices' backups, offered when a fresh install first opens.
  public var restoreOffer: [DeviceBackup] = []
  /// The clock, the engines and where signals go.
  @ObservationIgnored public let services: GameServices
  @ObservationIgnored private let storage: SaveStorage
  @ObservationIgnored private let backup: BackupDrive?
  /// What this device is called in its backups.
  @ObservationIgnored private let deviceName: String
  @ObservationIgnored private var pendingBackup: Task<Void, Never>?
  /// The last iCloud write, so the next one waits its turn.
  @ObservationIgnored private var lastWrite: Task<Void, Never>?

  private let deviceFile = "backup-device.json"
  private let profilesFile = "profiles.json"
  private var file: String { ProfileList.savePath(profiles.active) }

  /// `storage` holds the saves; `backup`, when there is one, keeps copies off the device.
  public init(storage: SaveStorage, backup: BackupDrive? = nil, services: GameServices = GameServices(), deviceName: String = "Device") {
    self.storage = storage
    self.backup = backup
    self.services = services
    self.deviceName = deviceName
  }

  /// Load the book (and build the opening tree) off the main actor, then the saved state.
  public func load(book url: URL?) async {
    guard index == nil else { return }
    let built = await Task.detached(priority: .userInitiated) { () -> (ReferenceIndex, OpeningTree)? in
      guard let url, let data = try? Data(contentsOf: url), let index = try? decodeBook(data) else { return nil }
      return (index, openingTree(index))
    }.value
    let fresh = !storage.exists(profilesFile) && !storage.exists(ProfileList.savePath(ProfileList.mainId))
    loadDevice()
    if let data = try? storage.read(profilesFile), let list = try? JSONDecoder().decode(ProfileList.self, from: data) {
      profiles = list
    }
    if let built {
      index = built.0
      tree = built.1
      catalog = pickerCatalog(built.1)
    }
    readState()
    if fresh && backup != nil { Task { restoreOffer = await deviceBackups() ?? [] } }
  }

  /// Read the active profile's save into `state`; none yet is a fresh start.
  private func readState() {
    state = AppState()
    saveBlocked = false
    autoHistory = AutoHistory()
    session = UUID()
    guard storage.exists(file) else { return }
    if let data = try? storage.read(file) {
      decode(data)
      if let index, state.migrate(index) { save() }
    } else {
      print("load failed: \(file) could not be read")
      saveBlocked = true
    }
  }

  private func decode(_ data: Data) {
    do {
      state = try decodeSave(data)
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
    try? storage.write(sibling(file, "playbook-unreadable-\(stamp).json"), data)
  }

  private func saveProfiles() {
    do {
      try storage.write(profilesFile, JSONEncoder().encode(profiles))
    } catch {
      print("save failed: \(error)")
    }
  }

  /// Save this profile and open another.
  public func switchProfile(_ id: String) {
    guard id != profiles.active else { return }
    save()
    backUpNow()
    profiles.activate(id)
    saveProfiles()
    readState()
  }

  /// A new profile, opened on a fresh start.
  public func createProfile(_ name: String) {
    save()
    backUpNow()
    profiles.add(name, id: UUID().uuidString.lowercased())
    saveProfiles()
    readState()
  }

  public func renameProfile(_ id: String, _ name: String) {
    profiles.rename(id, name)
    saveProfiles()
    send(profileId: nil, save: nil)
  }

  /// Delete a profile and its save. Deleting the one in use opens the next,
  /// and Settings opens again over its Home.
  public func deleteProfile(_ id: String) {
    let wasActive = id == profiles.active
    if !wasActive { save() }
    guard profiles.remove(id) else { return }
    saveProfiles()
    removeSave(id)
    release(id)
    send(profileId: nil, save: nil)
    guard wasActive else { return }
    readState()
    // Home opens Settings again; a profile still on its welcome has no Home yet.
    settingsHeld = state.settings.seenIntro && state.settings.onboarded
  }

  /// Whether Settings should open again on the new session, asked once.
  public func takeSettingsHeld() -> Bool {
    defer { settingsHeld = false }
    return settingsHeld
  }

  /// Wipe the profile in use: a fresh start under the same name.
  public func resetProfile() {
    release(profiles.active)
    removeSave(profiles.active)
    readState()
  }

  private func removeSave(_ id: String) {
    storage.remove(folderOf(ProfileList.savePath(id)))
  }

  public func save() {
    guard !saveBlocked else { return }
    do {
      try storage.write(file, JSONEncoder().encode(state))
      scheduleBackup()
    } catch {
      print("save failed: \(error)")
    }
  }

  // MARK: iCloud backup

  /// This device's backup folder, made up on first launch.
  private func loadDevice() {
    if let data = try? storage.read(deviceFile), let saved = try? JSONDecoder().decode(BackupDevice.self, from: data) {
      device = saved
    } else {
      device = BackupDevice(folder: String(UUID().uuidString.prefix(8)), manifest: BackupManifest(device: deviceName))
      saveDevice()
    }
  }

  private func saveDevice() {
    try? storage.write(deviceFile, JSONEncoder().encode(device))
  }

  /// Back up the profile in use a little after a change: every change saves, many a minute.
  private func scheduleBackup() {
    guard backup != nil, pendingBackup == nil else { return }
    pendingBackup = Task { [weak self] in
      try? await Task.sleep(for: .seconds(15))
      guard !Task.isCancelled else { return }
      self?.backUpNow()
    }
  }

  /// Back up the profile in use now: on leaving the app, and before opening another profile.
  /// A profile whose save failed to load stays held.
  public func backUpNow() {
    pendingBackup?.cancel()
    pendingBackup = nil
    guard !saveBlocked, !backupHeld, let data = try? JSONEncoder().encode(state) else { return }
    send(profileId: profiles.active, save: data)
  }

  /// The profile in use isn't being backed up: its save failed to load, so it opened on a fresh start.
  public var backupHeld: Bool { device.held.contains(profiles.active) }

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
    guard let drive = backup else { return }
    let now = Env.now()
    let day = backupDay(now)
    let old = device.manifest
    device.manifest = old.updated(profiles, saved: profileId, at: now, day: day)
    saveDevice()
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
  public func deviceBackups() async -> [DeviceBackup]? {
    guard let backup, let urls = await backup.findManifests() else {
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
    try? storage.write(ProfileList.savePath(profileId), data)
  }

  /// One profile from a backup, its latest save or `day`'s snapshot, falling back to older copies
  /// when that one can't be read. It replaces the profile with its id, or is added, and opens.
  public func restore(_ backed: BackedUpProfile, from source: DeviceBackup, day: String?) async -> RestoreOutcome {
    guard let backup, let found = await backup.read(folder: source.folder, files: backed.restoreFiles(from: day)) else { return .failed }
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
  public func restoreAll(_ source: DeviceBackup) async -> RestoreOutcome {
    guard let backup else { return .failed }
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
  public func peekRoundSelection() -> Selection { state.settings.selection }

  /// The same, for a state not saved yet, such as onboarding's Playbook before it goes in.
  public func peekRoundSelection(_ state: AppState) -> Selection { state.settings.selection }

  /// The next round's selection, taken.
  public func takeRoundSelection() -> Selection { state.settings.selection }

  /// Your openings, most worth focusing on first: `yourOpenings`.
  public func yourOpenings() -> [YourOpening] {
    guard let tree else { return [] }
    return Model.yourOpenings(state.playbookList, tree, state.score)
  }

  /// Change the state and save it.
  public func update(_ change: (inout AppState) -> Void) {
    change(&state)
    save()
  }

  /* ── onboarding ── */

  /// Onboarding's openings go in, and the tutorial's first game is next.
  public func startTutorial(_ openings: TutorialOpenings) {
    guard let tree else { return }
    update {
      $0.onboarded(tree, openings.seeds)
      $0.settings.startTutorial(openings)
    }
  }

  /// The tutorial skipped from its first question, once the openings are added.
  public func finishSkippedTutorial() {
    update {
      $0.settings.onboarded = true
      $0.settings.skipTutorial()
    }
  }
}

/// The folder a path is in: "" at the top.
private func folderOf(_ path: String) -> String {
  path.split(separator: "/").dropLast().joined(separator: "/")
}

/// A file named `name` beside `path`.
private func sibling(_ path: String, _ name: String) -> String {
  let folder = folderOf(path)
  return folder.isEmpty ? name : folder + "/" + name
}
