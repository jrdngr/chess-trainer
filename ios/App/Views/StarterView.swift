import Model
import SwiftUI

/// The first screen: a starter set as your first Playbook. The full
/// onboarding, with openings picked one by one, comes in phase 4.
struct StarterView: View {
  let tree: OpeningTree
  @Environment(AppStore.self) private var store

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 14) {
        Text("Pick a starting Playbook").font(.title.bold()).foregroundStyle(Theme.text)
        Text("One opening as White, and an answer to 1.e4 and to 1.d4. You can change it all later.")
          .foregroundStyle(Theme.text2)
        ForEach(STARTER_SETS, id: \.id) { set in
          Button {
            store.update { $0.seed(tree, set) }
          } label: {
            VStack(alignment: .leading, spacing: 6) {
              Text(set.name).font(.headline).foregroundStyle(Theme.text)
              Text(set.description).font(.subheadline).foregroundStyle(Theme.text2).multilineTextAlignment(.leading)
              ForEach(setOpenings(set), id: \.id) { o in
                Text("\(SLOT_LABELS[o.slot]!): \(o.label ?? nodeById(tree, o.id).name)").font(.caption).foregroundStyle(Theme.text3)
              }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 16).fill(Theme.surface))
          }
        }
      }
      .padding()
    }
  }
}
