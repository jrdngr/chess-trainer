import Game
import SwiftUI

@main
struct ChessPlaybookApp: App {
  @State private var store = AppStore.live()
  @State private var toasts = Toasts()
  @State private var cash = CashStore()
  @Environment(\.scenePhase) private var scenePhase

  var body: some Scene {
    WindowGroup {
      // A new session (another profile, or a reset) starts every screen over.
      RootView().id(store.session)
        .environment(store)
        .environment(toasts)
        .environment(cash)
        .preferredColorScheme(.dark)
        .task {
          await store.load()
          await cash.start(store)
        }
        // Another profile opened: the unlock, if owned, is its too.
        .onChange(of: store.session) { Task { await cash.restore() } }
        .onChange(of: scenePhase) { _, phase in
          if phase == .background { store.backUpNow() }
        }
    }
  }
}
