import Shared

/// Where sync stands, for the Sync row: `src/store/cloud.ts`.
public enum CloudStatus: Equatable, Sendable {
  case unavailable
  case idle(lastSyncedAt: Double?)
  case syncing
  case synced(lastSyncedAt: Double)
  case error(message: String)
  case tooLarge(bytes: Int)
}

/// The Sync row's status line.
public func describeStatus(_ status: CloudStatus) -> String {
  switch status {
  case .unavailable: return "Not available here \u{2014} this device only"
  case .syncing: return "Syncing\u{2026}"
  case .synced(let at): return "Synced \(relative(at))"
  case .idle(let at): return at.map { "Synced \(relative($0))" } ?? "Ready"
  case .tooLarge(let bytes): return "Too large to sync (\(JS.string(JS.round(Double(bytes) / 1024))) KiB of 240)"
  case .error(let message): return message
  }
}

private func relative(_ at: Double) -> String {
  let delta = Env.now() - at
  if delta < 60_000 { return "just now" }
  if delta < 3_600_000 { return "\(JS.string(JS.round(delta / 60_000))) min ago" }
  if delta < 86_400_000 { return "\(JS.string(JS.round(delta / 3_600_000))) h ago" }
  return "\(JS.string(JS.round(delta / 86_400_000))) d ago"
}
