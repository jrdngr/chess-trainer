import Game
import SwiftUI

@main
struct ChessPlaybookApp: App {
  @State private var store = AppStore.live()
  @State private var toasts = Toasts()
  @Environment(\.scenePhase) private var scenePhase

  var body: some Scene {
    WindowGroup {
      // A new session (another profile, or a reset) starts every screen over.
      RootView().id(store.session)
        .environment(store)
        .environment(toasts)
        .preferredColorScheme(.dark)
        .task { await store.load() }
        .onChange(of: scenePhase) { _, phase in
          if phase == .background { store.backUpNow() }
        }
    }
  }
}
