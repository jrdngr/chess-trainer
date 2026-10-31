import SwiftUI

/// The tab's large title: `AppBar` with `large`.
struct LargeTitleBar: View {
  var title: String

  var body: some View {
    Text(title).font(.system(size: 30, weight: .heavy)).tracking(-0.9).foregroundStyle(Theme.text)
      .frame(maxWidth: .infinity, minHeight: 42, alignment: .leading)
      .padding(.horizontal, 20).padding(.top, 14).padding(.bottom, 10)
  }
}

/// A page's bar: back, a centred title over a subtitle, and actions. `AppBar` compact.
struct PageBar<Actions: View>: View {
  var title: String
  var subtitle: String
  var onBack: () -> Void
  @ViewBuilder var actions: Actions

  var body: some View {
    HStack(spacing: 12) {
      Button(action: onBack) {
        Icon(name: "back", size: 20).foregroundStyle(Theme.text).frame(width: 38, height: 38)
          .background(Circle().fill(Theme.surface))
      }
      .buttonStyle(.plain).accessibilityLabel("Back")
      VStack(spacing: 1) {
        Text(title).font(.system(size: 17, weight: .bold)).tracking(-0.17).foregroundStyle(Theme.text).lineLimit(1)
        Text(subtitle).font(.system(size: 13)).foregroundStyle(Theme.text2).multilineTextAlignment(.center)
      }
      .frame(maxWidth: .infinity)
      actions.frame(width: 38, height: 38)
    }
    .padding(.horizontal, 20).padding(.top, 10).padding(.bottom, 10)
  }
}
