import Foundation
import Model

/// Where a device's backups go: iCloud Drive in the app. A headless game has none.
public protocol BackupDrive: Sendable {
  /// Write one profile's save (if given) as its latest and as `day`'s snapshot, then the device's
  /// manifest, then remove the files it no longer lists. False when the drive is off or a write failed.
  func write(folder: String, profileId: String?, save: Data?, day: String, manifest: BackupManifest, removing gone: Set<String>) async -> Bool
  /// Every device's manifest, given the manifest files found.
  func manifests(_ urls: [URL]) async -> [DeviceBackup]
  /// The first of `files` in a device's folder that this version can read, and its name.
  func read(folder: String, files: [String]) async -> (file: String, data: Data)?
  /// The manifest files on the drive. Nil when the drive is off.
  func findManifests() async -> [URL]?
}

/// This device's backup folder and its manifest, kept beside the saves.
public struct BackupDevice: Codable, Equatable, Sendable {
  public var folder: String
  public var manifest: BackupManifest
  /// Profiles whose save failed to load here: not backed up until restored or reset, so the
  /// fresh start they opened on doesn't replace their backup.
  public var held: [String] = []

  public init(folder: String, manifest: BackupManifest) {
    self.folder = folder
    self.manifest = manifest
  }

  enum CodingKeys: String, CodingKey { case folder, manifest, held }

  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    folder = try c.decode(String.self, forKey: .folder)
    manifest = try c.decode(BackupManifest.self, forKey: .manifest)
    held = try c.decodeIfPresent([String].self, forKey: .held) ?? []
  }
}

/// How a restore went: nothing readable, or restored, from an older copy than the one asked for
/// when that one couldn't be read.
public enum RestoreOutcome: Equatable, Sendable {
  case failed
  case restored(olderDay: String?)
}

/// Today, `yyyy-MM-dd` on this device's calendar: the day a snapshot is filed under.
public func backupDay(_ ms: Double) -> String {
  let formatter = DateFormatter()
  formatter.locale = Locale(identifier: "en_US_POSIX")
  formatter.dateFormat = "yyyy-MM-dd"
  return formatter.string(from: Date(timeIntervalSince1970: ms / 1000))
}
