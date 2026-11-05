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
  /// A profile's latest save inside a device's folder.
  public static func saveFile(_ profileId: String) -> String { "\(profileId).json" }
  /// A profile's save as it stood at the end of a day, `yyyy-MM-dd`.
  public static func snapshotFile(_ profileId: String, _ day: String) -> String { "\(profileId)-\(day).json" }
  /// How many days played each profile keeps a snapshot for.
  public static let snapshotDays = 7

  /// The newest save in it.
  public var savedAt: Double { profiles.map(\.savedAt).max() ?? 0 }

  /// Every file it lists: each profile's latest save and its snapshots.
  public var files: Set<String> {
    Set(profiles.flatMap { profile in
      [Self.saveFile(profile.id)] + profile.days.map { Self.snapshotFile(profile.id, $0) }
    })
  }

  /// The manifest once `saved` has been written at `at`, on `day`. Profiles follow the
  /// device's list: its order, names and deletions. The saved profile's day goes first
  /// among its snapshots, keeping the last `snapshotDays`; the others are as they were.
  /// A profile never saved isn't listed.
  public func updated(_ list: ProfileList, saved: String?, at: Double, day: String) -> BackupManifest {
    let old = Dictionary(profiles.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    let kept = list.profiles.compactMap { profile -> BackedUpProfile? in
      if profile.id == saved {
        let days = [day] + (old[profile.id]?.days ?? []).filter { $0 != day }
        return BackedUpProfile(id: profile.id, name: profile.name, savedAt: at, days: Array(days.prefix(Self.snapshotDays)))
      }
      guard var backed = old[profile.id] else { return nil }
      backed.name = profile.name
      return backed
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
  /// The days it has a snapshot for, `yyyy-MM-dd`, newest first. The first is the latest save's day.
  public var days: [String]

  public init(id: String, name: String, savedAt: Double, days: [String] = []) {
    self.id = id
    self.name = name
    self.savedAt = savedAt
    self.days = days
  }

  enum CodingKeys: String, CodingKey { case id, name, savedAt, days }

  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    id = try c.decode(String.self, forKey: .id)
    name = try c.decode(String.self, forKey: .name)
    savedAt = try c.decode(Double.self, forKey: .savedAt)
    days = try c.decodeIfPresent([String].self, forKey: .days) ?? []
  }

  /// The days before the latest save's, to restore from instead.
  public var olderDays: [String] { Array(days.dropFirst()) }

  /// The files to try, in order, when restoring from `day` (nil: the latest save):
  /// that copy first, then each older one, so an unreadable copy falls back to the one before.
  public func restoreFiles(from day: String?) -> [String] {
    let snapshots = days.map { BackupManifest.snapshotFile(id, $0) }
    guard let day else { return [BackupManifest.saveFile(id)] + snapshots }
    guard let start = days.firstIndex(of: day) else { return [] }
    return Array(snapshots[start...])
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

/// The backups this device can restore from, those with at least one profile: its own first
/// (its older days, or its last good save after a save failed to load), then the others, newest first.
public func restoreChoices(_ backups: [DeviceBackup], own: String) -> [DeviceBackup] {
  backups.filter { !$0.manifest.profiles.isEmpty }
    .sorted { ($0.folder == own ? 1 : 0, $0.manifest.savedAt) > ($1.folder == own ? 1 : 0, $1.manifest.savedAt) }
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
