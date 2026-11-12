import Foundation

/// Where the app keeps its files, by path under one folder: the profile list,
/// each profile's save, and this device's backup record.
public protocol SaveStorage: AnyObject {
  func exists(_ path: String) -> Bool
  func read(_ path: String) throws -> Data
  /// Write a file, making its folders.
  func write(_ path: String, _ data: Data) throws
  /// Remove a file or a folder and everything in it.
  func remove(_ path: String)
}

/// Files in a folder on disk: Application Support in the app.
public final class FileStorage: SaveStorage {
  public let folder: URL

  public init(folder: URL) { self.folder = folder }

  private func url(_ path: String) -> URL { folder.appendingPathComponent(path) }

  public func exists(_ path: String) -> Bool { FileManager.default.fileExists(atPath: url(path).path) }

  public func read(_ path: String) throws -> Data { try Data(contentsOf: url(path)) }

  public func write(_ path: String, _ data: Data) throws {
    let file = url(path)
    try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
    try data.write(to: file, options: .atomic)
  }

  public func remove(_ path: String) { try? FileManager.default.removeItem(at: url(path)) }
}

/// Files kept in memory, gone with the game: a headless game's saves.
public final class MemoryStorage: SaveStorage {
  public private(set) var files: [String: Data] = [:]

  public init() {}

  public func exists(_ path: String) -> Bool { files[path] != nil }

  public func read(_ path: String) throws -> Data {
    guard let data = files[path] else { throw CocoaError(.fileReadNoSuchFile) }
    return data
  }

  public func write(_ path: String, _ data: Data) throws { files[path] = data }

  public func remove(_ path: String) {
    let folder = path.hasSuffix("/") ? path : path + "/"
    files = files.filter { $0.key != path && !$0.key.hasPrefix(folder) }
  }
}
