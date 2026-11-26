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
  /// Pawns earned and on their way to the counter.
  public internal(set) var pawnDrops: [PawnDrop] = []
  /// Streak pawns paid but not shown yet: they pop out of the streak ring on Home.
  public internal(set) var streakWaiting = 0
  /// Why the latest pawns were paid, from when the first of them lands in the counter.
  public internal(set) var pawnReason: PawnReason?
  /// The feature just bought, until its place shows it off.
  public internal(set) var justUnlocked: ShopFeature?
  @ObservationIgnored var dropCount = 0
  /// The save exists but could not be read (locked, say): saving now would replace it with a fresh state.
  @ObservationIgnored private var saveBlocked = false

  /// The profiles on this device and the one in use.
  public internal(set) var profiles = ProfileList()
  /// Changes whenever the state is swapped out (a switch or a reset), so screens start over.
  public private(set) var session = UUID()
  /// The developer tools' settings for this device.
  public internal(set) var dev = DevSettings()
  /// Whether this build may use the developer settings: Release builds don't, whatever the device kept.
  public var devAllowed = true
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
  @ObservationIgnored let storage: SaveStorage
  @ObservationIgnored private let backup: BackupDrive?
  /// What this device is called in its backups.
  @ObservationIgnored private let deviceName: String
  @ObservationIgnored private var pendingBackup: Task<Void, Never>?
  /// The last iCloud write, so the next one waits its turn.
  @ObservationIgnored private var lastWrite: Task<Void, Never>?
  /// The saves are read: until then `state` is a placeholder, never backed up.
  @ObservationIgnored private var loaded = false
  /// The last write of the save failed.
  @ObservationIgnored private var lastSaveFailed = false

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
    loadDev()
    if let data = try? storage.read(profilesFile), let list = try? JSONDecoder().decode(ProfileList.self, from: data) {
      profiles = list
    }
    if let built {
      index = built.0
      tree = built.1
      catalog = pickerCatalog(built.1)
    }
    readState()
    loaded = true
    if fresh && backup != nil { Task { restoreOffer = await deviceBackups() ?? [] } }
  }

  /// Read the active profile's save into `state`; none yet is a fresh start.
  func readState() {
    state = AppState()
    saveBlocked = false
    autoHistory = AutoHistory()
    session = UUID()
    guard storage.exists(file) else { return }
    if let data = try? storage.read(file) {
      decode(data)
    } else {
      print("load failed: \(file) could not be read")
      saveBlocked = true
    }
  }

  /// Screens start over on the state as it is.
  public func restartScreens() { session = UUID() }

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

  func saveProfiles() {
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
      lastSaveFailed = false
      scheduleBackup()
    } catch {
      lastSaveFailed = true
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
  /// A profile whose save failed to load stays held, and nothing goes before the saves are read.
  public func backUpNow() {
    pendingBackup?.cancel()
    pendingBackup = nil
    guard loaded, !saveBlocked, !backupHeld, let data = try? JSONEncoder().encode(state) else { return }
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
    // A kept snapshot lasts the day it was kept.
    device.kept = device.kept.filter { $0.hasSuffix("-\(day).json") }
    let snapshot = profileId.map { !device.kept.contains(BackupManifest.snapshotFile($0, day)) } ?? true
    saveDevice()
    let folder = device.folder
    let manifest = device.manifest
    let gone = old.files.subtracting(manifest.files)
    let previous = lastWrite
    lastWrite = Task { [weak self] in
      await previous?.value
      let written = await drive.write(
        folder: folder, profileId: profileId, save: save, snapshot: snapshot, day: day, manifest: manifest, removing: gone)
      self?.iCloudOff = !written
    }
  }

  /// Waits for the backup writes sent so far.
  public func backupsWritten() async { await lastWrite?.value }

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
    // The profile it replaces is backed up as it was, and today's snapshot keeps that copy
    // for the rest of the day, so the restore can be undone.
    let replaced = backed.id == profiles.active ? nil : try? storage.read(ProfileList.savePath(backed.id))
    if let replaced, !device.held.contains(backed.id) { send(profileId: backed.id, save: replaced) }
    let hadCopy = backed.id == profiles.active ? (loaded && !saveBlocked && !backupHeld) : (replaced != nil && !device.held.contains(backed.id))
    if hadCopy { device.kept.append(BackupManifest.snapshotFile(backed.id, backupDay(Env.now()))) }
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

  /// The next round's selection, taken.
  public func takeRoundSelection() -> Selection { state.settings.selection }

  /// Your openings, most worth focusing on first: `yourOpenings`.
  public func yourOpenings() -> [YourOpening] {
    guard let tree else { return [] }
    return Model.yourOpenings(state.playbookList, tree, state.score)
  }

  /// Change the state and save it. A change to the settings goes in the log.
  public func update(_ change: (inout AppState) -> Void) {
    let settings = state.settings
    change(&state)
    state.holdToUnlocks()
    if state.settings != settings, let changed = settingsChanged(settings, state.settings) {
      state.logEvent(AppEvent(kind: "settings", rows: changed))
    }
    save()
  }

  /// One more event in the log, saved with the next change.
  public func log(_ event: AppEvent) {
    state.logEvent(event)
  }

  /* ── onboarding ── */

  /// "Recommend some openings": the recommended openings go in, and onboarding is done.
  public func recommendOpenings() {
    guard let tree else { return }
    update { $0.recommend(tree) }
  }

  /// "Choose my openings" done: the openings picked for the slots go in, and onboarding is done.
  public func chooseOpenings(_ ids: [String]) {
    guard let tree else { return }
    update { $0.choose(tree, ids) }
  }

  /// An App Store purchase, credited once per transaction. Returns whether it was credited.
  /// `bought` is a purchase made just now; otherwise the App Store is handing back one made
  /// before, which the developer tools can have this device ignore for the unlock.
  @discardableResult
  public func credit(_ product: CashProduct, transaction: String, bought: Bool = true) -> Bool {
    if product == .unlock && !bought && dev.ignoreStoreUnlock { return false }
    var done = false
    update { done = $0.credit(product, transaction: transaction) }
    return done
  }

  /// The App Store took a purchase back: a refunded unlock takes back the features only it gave.
  public func revoke(_ product: CashProduct, transaction: String) {
    update { $0.revoke(product, transaction: transaction) }
  }

  /// Whether the state is being kept: the save was read and the last write went through.
  /// A purchase is finished with the App Store only then, so one not kept comes back.
  public var savesKept: Bool { !saveBlocked && !lastSaveFailed }

  /// A tip shown off the board, put away for good.
  public func see(_ tip: GameTip) {
    update { $0.sawTip(tip) }
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

/// What changed between two versions of the settings, a row per setting, `key: old → new`.
/// Tips seen are logged on their own.
func settingsChanged(_ before: Settings, _ after: Settings) -> [String]? {
  func fields(_ settings: Settings) -> [String: String] {
    guard let data = try? JSONEncoder().encode(settings),
      let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else { return [:] }
    var out: [String: String] = [:]
    for (key, value) in object where key != "seenTips" {
      let json = (try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .fragmentsAllowed])) ?? Data()
      out[key] = String(data: json, encoding: .utf8) ?? "\(value)"
    }
    return out
  }
  let was = fields(before), now = fields(after)
  let rows = Set(was.keys).union(now.keys).sorted().compactMap { key -> String? in
    was[key] == now[key] ? nil : "\(key): \(was[key] ?? "none") \u{2192} \(now[key] ?? "none")"
  }
  return rows.isEmpty ? nil : rows
}
