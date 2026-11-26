import Foundation
import Model

/// The developer tools on the store: changes to the save that log nothing, profiles, the clock,
/// and the save itself in and out. Only Debug builds show them.
extension AppStore {
  static let devFile = "dev.json"

  /// A change from the developer tools: saved, with no settings logged.
  public func devUpdate(_ change: (inout AppState) -> Void) {
    change(&state)
    state.holdToUnlocks()
    save()
  }

  /// The developer settings for this device, read from its own file; none in a build without the tools.
  func loadDev() {
    guard devAllowed else {
      dev = DevSettings()
      return
    }
    if let data = try? storage.read(Self.devFile), let saved = try? JSONDecoder().decode(DevSettings.self, from: data) {
      dev = saved
    }
  }

  /// Change the developer settings and keep them on this device.
  public func setDev(_ change: (inout DevSettings) -> Void) {
    change(&dev)
    try? storage.write(Self.devFile, JSONEncoder().encode(dev))
  }

  /// Days the clock runs ahead; the app moves `Env`'s real clock to match.
  public func travel(days: Int) {
    setDev { $0.daysAhead = max(0, days) }
  }

  /// An opening on the list in or out of the Playbook, free.
  public func devSetOpening(_ id: String, owned: Bool) {
    guard let tree else { return }
    devUpdate { $0.devSetOpening(id, owned: owned, tree) }
  }

  /// The profile in use copied to a new one, which opens.
  public func duplicateProfile() {
    save()
    backUpNow()
    guard let data = try? JSONEncoder().encode(state) else { return }
    let name = profiles.cleanName("\(profiles.activeProfile.name) copy")
    let id = UUID().uuidString.lowercased()
    try? storage.write(ProfileList.savePath(id), data)
    profiles.add(name, id: id)
    saveProfiles()
    readState()
  }

  /// The save as JSON, as it is written to disk.
  public func exportSave() -> Data? {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    return try? encoder.encode(state)
  }

  /// A save pasted in replaces the profile in use. One this version can't read, or from an older
  /// version, changes nothing. Returns whether it was taken.
  @discardableResult
  public func importSave(_ data: Data) -> Bool {
    guard let read = try? JSONDecoder().decode(AppState.self, from: data), read.version == SAVE_VERSION else { return false }
    state = read
    autoHistory = AutoHistory()
    save()
    restartScreens()
    return true
  }
}
