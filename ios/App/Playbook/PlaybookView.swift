import Book
import Model
import SwiftUI

/// The Playbook tab. A stand-in until its screen is ported.
struct PlaybookView: View {
  let tree: OpeningTree
  let index: ReferenceIndex

  var body: some View {
    VStack(alignment: .leading) {
      Text("Playbook").font(.system(size: 32, weight: .heavy)).foregroundStyle(Theme.text)
      Spacer()
    }
    .frame(maxWidth: .infinity, alignment: .leading).padding()
  }
}
