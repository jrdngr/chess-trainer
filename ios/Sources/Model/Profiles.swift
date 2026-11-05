import Foundation

/// One set of app data: its own Playbook, ratings, stats, cards and settings.
public struct Profile: Equatable, Sendable, Codable, Identifiable {
  public var id: String
  public var name: String

  public init(id: String, name: String) {
    self.id = id
    self.name = name
  }
}

/// The profiles on this device, in the order they were made, and the one in use.
public struct ProfileList: Equatable, Sendable, Codable {
  /// The first profile's id.
  public static let mainId = "main"

  public private(set) var profiles: [Profile] = [Profile(id: ProfileList.mainId, name: "Main")]
  public private(set) var active: String = ProfileList.mainId

  public init() {}

  public var activeProfile: Profile { profiles.first { $0.id == active } ?? profiles[0] }

  /// Where a profile's save lives, under the app's data folder.
  public static func savePath(_ id: String) -> String { "profiles/\(id)/playbook.json" }

  /// A typed name, trimmed; blank takes "Profile N" for the next free N.
  public func cleanName(_ typed: String) -> String {
    let trimmed = typed.trimmingCharacters(in: .whitespacesAndNewlines)
    if !trimmed.isEmpty { return trimmed }
    let names = Set(profiles.map(\.name))
    var n = profiles.count + 1
    while names.contains("Profile \(n)") { n += 1 }
    return "Profile \(n)"
  }

  /// Add a profile and make it the active one.
  @discardableResult
  public mutating func add(_ name: String, id: String) -> Profile {
    let profile = Profile(id: id, name: cleanName(name))
    profiles.append(profile)
    active = id
    return profile
  }

  /// A whole new list, on its first profile.
  mutating func replace(_ list: [Profile]) {
    guard !list.isEmpty else { return }
    profiles = list
    active = list[0].id
  }

  public mutating func activate(_ id: String) {
    if profiles.contains(where: { $0.id == id }) { active = id }
  }

  public mutating func rename(_ id: String, _ name: String) {
    guard let i = profiles.firstIndex(where: { $0.id == id }) else { return }
    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
    if !trimmed.isEmpty { profiles[i].name = trimmed }
  }

  /// Remove a profile. The last one stays (it is reset instead). Removing the active one
  /// moves to the profile after it, or the one before when it was last in the list.
  @discardableResult
  public mutating func remove(_ id: String) -> Bool {
    guard profiles.count > 1, let i = profiles.firstIndex(where: { $0.id == id }) else { return false }
    profiles.remove(at: i)
    if active == id { active = profiles[min(i, profiles.count - 1)].id }
    return true
  }

  enum CodingKeys: String, CodingKey { case profiles, active }

  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    self.init()
    let saved = try c.decodeIfPresent([Profile].self, forKey: .profiles) ?? []
    if !saved.isEmpty { profiles = saved }
    let savedActive = try c.decodeIfPresent(String.self, forKey: .active) ?? active
    active = profiles.contains { $0.id == savedActive } ? savedActive : profiles[0].id
  }
}
