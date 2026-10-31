import SwiftUI

@main
struct ChessPlaybookApp: App {
  @State private var store = AppStore()
  @State private var toasts = Toasts()

  var body: some Scene {
    WindowGroup {
      RootView()
        .environment(store)
        .environment(toasts)
        .preferredColorScheme(.dark)
        .task { await store.load() }
    }
  }
}
