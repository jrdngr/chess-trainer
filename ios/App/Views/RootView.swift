import Model
import SwiftUI

struct RootView: View {
  @Environment(AppStore.self) private var store
  @State private var playing = false

  var body: some View {
    ZStack {
      Theme.background.ignoresSafeArea()
      if let tree = store.tree, let index = store.index {
        if !store.state.settings.onboarded {
          StarterView(tree: tree)
        } else if playing {
          AutopilotView(tree: tree, index: index) { playing = false }
        } else {
          HomeView(tree: tree) { playing = true }
        }
      } else {
        ProgressView().tint(Theme.text2)
      }
    }
  }
}
