import SwiftUI

@main
struct ChessPlaybookApp: App {
  @State private var store = AppStore()
  @State private var toasts = Toasts()

  var body: some Scene {
    WindowGroup {
      // A new session (another profile, or a reset) starts every screen over.
      RootView().id(store.session)
        .environment(store)
        .environment(toasts)
        .preferredColorScheme(.dark)
        .task { await store.load() }
    }
  }
}
