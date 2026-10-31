import Book
import Model
import SwiftUI

/// The Analysis tab. A stand-in until its screen is ported.
struct AnalysisTab: View {
  let tree: OpeningTree
  let index: ReferenceIndex

  var body: some View {
    VStack(alignment: .leading) {
      Text("Analysis").font(.system(size: 32, weight: .heavy)).foregroundStyle(Theme.text)
      Spacer()
    }
    .frame(maxWidth: .infinity, alignment: .leading).padding()
  }
}
