import Foundation
import Game
import UIKit

/// The app's one game: its store on Application Support with an iCloud backup,
/// real time, Caissa, and haptics for buzzes.
@MainActor
enum LiveGame {
  static let services = GameServices(dealSeconds: RoundDeal.length)
  /// Turns the game's buzzes into haptics, as Settings allows.
  static let haptics = HapticSink()
}

@MainActor
final class HapticSink: SignalSink {
  weak var store: AppStore?

  func emit(_ signal: GameSignal) {
    let on = store?.state.settings.hapticFeedback ?? true
    switch signal {
    case .buzz(let ms): Haptics.buzz(ms, on: on)
    case .success: Haptics.success(on: on)
    default: break
    }
  }
}

extension AppStore {
  /// The store the app runs on.
  static func live() -> AppStore {
    let store = AppStore(
      storage: FileStorage(folder: URL.applicationSupportDirectory), backup: ICloudBackup(), services: LiveGame.services,
      deviceName: UIDevice.current.model)
    LiveGame.haptics.store = store
    LiveGame.services.sink = LiveGame.haptics
    return store
  }

  /// Load the bundled book, then the saved state.
  func load() async {
    await load(book: Bundle.main.url(forResource: "book", withExtension: "json"))
  }
}
