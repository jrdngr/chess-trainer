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

  /// Write one profile's save (if given) and the device's manifest. False when iCloud is off or the write failed.
  func write(folder: String, profileId: String?, save: Data?, manifest: BackupManifest) -> Bool {
    guard let root = root() else { return false }
    let dir = root.appending(path: folder)
    do {
      try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
      if let profileId, let save { try coordinatedWrite(save, to: dir.appending(path: BackupManifest.saveFile(profileId))) }
      try coordinatedWrite(JSONEncoder().encode(manifest), to: dir.appending(path: BackupManifest.file))
      return true
    } catch {
      print("backup failed: \(error)")
      return false
    }
  }

  /// Remove a deleted profile's save and write the manifest without it.
  func remove(folder: String, profileId: String, manifest: BackupManifest) -> Bool {
    guard let root = root() else { return false }
    let file = root.appending(path: folder).appending(path: BackupManifest.saveFile(profileId))
    var failure: NSError?
    NSFileCoordinator().coordinate(writingItemAt: file, options: .forDeleting, error: &failure) { url in
      try? FileManager.default.removeItem(at: url)
    }
    return write(folder: folder, profileId: nil, save: nil, manifest: manifest)
  }

  /// Every device's manifest, given the manifest files a metadata query found.
  func manifests(_ urls: [URL]) -> [DeviceBackup] {
    urls.compactMap { url in
      guard let data = coordinatedRead(url), let manifest = try? JSONDecoder().decode(BackupManifest.self, from: data) else { return nil }
      return DeviceBackup(folder: url.deletingLastPathComponent().lastPathComponent, manifest: manifest)
    }
  }

  /// One profile's save from a device's folder, downloaded first if need be.
  func read(folder: String, profileId: String) -> Data? {
    guard let root = root() else { return nil }
    return coordinatedRead(root.appending(path: folder).appending(path: BackupManifest.saveFile(profileId)))
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
}
