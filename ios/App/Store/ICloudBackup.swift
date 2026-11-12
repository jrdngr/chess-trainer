import Foundation
import Model

/// The app's iCloud Drive folder: each device keeps a copy of its profile saves in a folder
/// of its own, `Documents/<folder>/`, with a `backup.json` listing them.
actor ICloudBackup {
  static let container = "iCloud.com.jordangrace.chessplaybook"

  private var documents: URL?

  /// The container's Documents folder, or nil when iCloud is off.
  private func root() -> URL? {
    if let documents { return documents }
    guard let url = FileManager.default.url(forUbiquityContainerIdentifier: Self.container) else { return nil }
    documents = url.appending(path: "Documents")
    return documents
  }

  /// Write one profile's save (if given) as its latest and as `day`'s snapshot, then the device's
  /// manifest, then remove the files it no longer lists. False when iCloud is off or a write failed.
  func write(folder: String, profileId: String?, save: Data?, day: String, manifest: BackupManifest, removing gone: Set<String>) -> Bool {
    guard let root = root() else { return false }
    let dir = root.appending(path: folder)
    do {
      try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
      if let profileId, let save {
        try coordinatedWrite(save, to: dir.appending(path: BackupManifest.saveFile(profileId)))
        try coordinatedWrite(save, to: dir.appending(path: BackupManifest.snapshotFile(profileId, day)))
      }
      try coordinatedWrite(JSONEncoder().encode(manifest), to: dir.appending(path: BackupManifest.file))
    } catch {
      print("backup failed: \(error)")
      return false
    }
    for name in gone {
      var failure: NSError?
      NSFileCoordinator().coordinate(writingItemAt: dir.appending(path: name), options: .forDeleting, error: &failure) { url in
        try? FileManager.default.removeItem(at: url)
      }
    }
    return true
  }

  /// Every device's manifest, given the manifest files a metadata query found.
  func manifests(_ urls: [URL]) -> [DeviceBackup] {
    urls.compactMap { url in
      guard let data = coordinatedRead(url), let manifest = try? JSONDecoder().decode(BackupManifest.self, from: data) else { return nil }
      return DeviceBackup(folder: url.deletingLastPathComponent().lastPathComponent, manifest: manifest)
    }
  }

  /// The first of `files` in a device's folder that this version can read, downloaded first if
  /// need be, and its name.
  func read(folder: String, files: [String]) -> (file: String, data: Data)? {
    guard let root = root() else { return nil }
    for file in files {
      if let data = coordinatedRead(root.appending(path: folder).appending(path: file)),
        (try? decodeSave(data)) != nil
      {
        return (file, data)
      }
    }
    return nil
  }

  private func coordinatedWrite(_ data: Data, to file: URL) throws {
    var failure: NSError?
    var writeError: Error?
    NSFileCoordinator().coordinate(writingItemAt: file, options: .forReplacing, error: &failure) { url in
      do { try data.write(to: url, options: .atomic) } catch { writeError = error }
    }
    if let error = failure ?? writeError { throw error }
  }

  /// A coordinated read downloads a file that is only in iCloud before reading it.
  private func coordinatedRead(_ file: URL) -> Data? {
    try? FileManager.default.startDownloadingUbiquitousItem(at: file)
    var failure: NSError?
    var data: Data?
    NSFileCoordinator().coordinate(readingItemAt: file, options: [], error: &failure) { url in
      data = try? Data(contentsOf: url)
    }
    return data
  }
}

/// The manifest files in iCloud, including ones not downloaded to this device yet. Nil when iCloud is off.
@MainActor
func findBackupManifests() async -> [URL]? {
  guard FileManager.default.ubiquityIdentityToken != nil else { return nil }
  let query = NSMetadataQuery()
  query.searchScopes = [NSMetadataQueryUbiquitousDocumentsScope]
  query.predicate = NSPredicate(format: "%K == %@", NSMetadataItemFSNameKey, BackupManifest.file)
  guard query.start() else { return [] }
  // The query gathers on the main run loop; check back until it's done, for at most 20 seconds.
  for _ in 0..<200 where query.isGathering {
    try? await Task.sleep(for: .milliseconds(100))
  }
  query.disableUpdates()
  let urls = (0..<query.resultCount).compactMap { (query.result(at: $0) as? NSMetadataItem)?.value(forAttribute: NSMetadataItemURLKey) as? URL }
  query.stop()
  return urls
}

/// This device's backup folder and its manifest, kept beside the saves.
struct BackupDevice: Codable, Equatable {
  var folder: String
  var manifest: BackupManifest
  /// Profiles whose save failed to load here: not backed up until restored or reset, so the
  /// fresh start they opened on doesn't replace their backup.
  var held: [String] = []

  init(folder: String, manifest: BackupManifest) {
    self.folder = folder
    self.manifest = manifest
  }

  enum CodingKeys: String, CodingKey { case folder, manifest, held }

  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    folder = try c.decode(String.self, forKey: .folder)
    manifest = try c.decode(BackupManifest.self, forKey: .manifest)
    held = try c.decodeIfPresent([String].self, forKey: .held) ?? []
  }
}

/// How a restore went: nothing readable, or restored, from an older copy than the one asked for
/// when that one couldn't be read.
enum RestoreOutcome: Equatable {
  case failed
  case restored(olderDay: String?)
}

/// Today, `yyyy-MM-dd` on this device's calendar: the day a snapshot is filed under.
func backupDay(_ ms: Double) -> String {
  let formatter = DateFormatter()
  formatter.locale = Locale(identifier: "en_US_POSIX")
  formatter.dateFormat = "yyyy-MM-dd"
  return formatter.string(from: Date(timeIntervalSince1970: ms / 1000))
}
