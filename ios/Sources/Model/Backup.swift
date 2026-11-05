import Foundation

/// One device's backup: its profiles that have a save there, and when each was saved.
/// Every device writes only its own folder, so a fresh install never writes over
/// another device's backup.
public struct BackupManifest: Equatable, Sendable, Codable {
  /// What kind of device made it, such as "iPhone".
  public var device: String
  public var profiles: [BackedUpProfile]

  public init(device: String, profiles: [BackedUpProfile] = []) {
    self.device = device
    self.profiles = profiles
  }

  /// The manifest's name inside a device's folder.
  public static let file = "backup.json"
  /// A profile's save inside a device's folder.
  public static func saveFile(_ profileId: String) -> String { "\(profileId).json" }

  /// The newest save in it.
  public var savedAt: Double { profiles.map(\.savedAt).max() ?? 0 }

  /// The manifest once `saved` has been written at `at`. Profiles follow the device's list:
  /// its order, names and deletions. The others keep their last save time; a profile
  /// never saved isn't listed.
  public func updated(_ list: ProfileList, saved: String?, at: Double) -> BackupManifest {
    let times = Dictionary(profiles.map { ($0.id, $0.savedAt) }, uniquingKeysWith: max)
    let kept = list.profiles.compactMap { profile -> BackedUpProfile? in
      guard let time = profile.id == saved ? at : times[profile.id] else { return nil }
      return BackedUpProfile(id: profile.id, name: profile.name, savedAt: time)
    }
    return BackupManifest(device: device, profiles: kept)
  }
}

/// A profile in a backup.
public struct BackedUpProfile: Equatable, Sendable, Codable, Identifiable {
  public var id: String
  public var name: String
  /// Milliseconds since the epoch.
  public var savedAt: Double

  public init(id: String, name: String, savedAt: Double) {
    self.id = id
    self.name = name
    self.savedAt = savedAt
  }
}

/// A device's backup and the folder it lives in.
public struct DeviceBackup: Equatable, Sendable, Identifiable {
  public var folder: String
  public var manifest: BackupManifest
  public var id: String { folder }

  public init(folder: String, manifest: BackupManifest) {
    self.folder = folder
    self.manifest = manifest
  }
}

/// The backups this device can restore from: other devices' (this one's own is what it
/// already has), with at least one profile, newest first.
public func restoreChoices(_ backups: [DeviceBackup], own: String) -> [DeviceBackup] {
  backups.filter { $0.folder != own && !$0.manifest.profiles.isEmpty }
    .sorted { $0.manifest.savedAt > $1.manifest.savedAt }
}

extension ProfileList {
  /// A device's whole list from a backup, on the first profile.
  public init(restoring backup: BackupManifest) {
    self.init()
    let restored = backup.profiles.map { Profile(id: $0.id, name: $0.name) }
    if !restored.isEmpty { replace(restored) }
  }

  /// One profile back from a backup, and made the active one. A profile with the same id
  /// takes the backup's name (its save is replaced); otherwise it's added.
  /// Returns whether one was replaced.
  @discardableResult
  public mutating func restore(_ backed: BackedUpProfile) -> Bool {
    let replaced = profiles.contains { $0.id == backed.id }
    if replaced {
      rename(backed.id, backed.name)
      activate(backed.id)
    } else {
      add(backed.name, id: backed.id)
    }
    return replaced
  }
}
