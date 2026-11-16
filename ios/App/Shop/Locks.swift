import Game
import Model
import SwiftUI

extension EnvironmentValues {
  /// Opens the Pawn Shop on an item.
  @Entry var openShop: ((String) -> Void)? = nil
}

extension View {
  /// A control a Pawn Shop feature unlocks: in place and dimmed until it is yours, a tap opening
  /// its item in the shop, or with `hidden` not shown at all until then. Once bought, it grows in
  /// with two glows the first time it shows.
  func unlockedBy(_ feature: ShopFeature, hidden: Bool = false) -> some View {
    modifier(Unlockable(feature: feature, hidden: hidden))
  }
}

private struct Unlockable: ViewModifier {
  let feature: ShopFeature
  let hidden: Bool
  @Environment(AppStore.self) private var store
  @Environment(\.openShop) private var openShop
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var glow = 0

  @ViewBuilder func body(content: Content) -> some View {
    if hidden && !store.state.owns(feature) {
      EmptyView()
    } else {
      shown(content)
    }
  }

  private func shown(_ content: Content) -> some View {
    let owned = store.state.owns(feature)
    return content
      .disabled(!owned)
      .opacity(owned ? 1 : 0.35)
      .overlay {
        if !owned {
          SwiftUI.Color.clear.contentShape(Rectangle())
            .onTapGesture { openShop?(feature.rawValue) }
            .accessibilityElement()
            .accessibilityLabel("Locked: open the Pawn Shop")
            .accessibilityAddTraits(.isButton)
        }
      }
      .keyframeAnimator(initialValue: Grow(), trigger: glow) { view, grow in
        view.scaleEffect(grow.scale)
          .shadow(color: Theme.accent.opacity(grow.glow * 0.75), radius: 11 * grow.glow)
      } keyframes: { _ in
        KeyframeTrack(\.scale) {
          CubicKeyframe(0.94, duration: 0.01)
          CubicKeyframe(1.05, duration: 0.45)
          CubicKeyframe(1, duration: 0.6)
        }
        KeyframeTrack(\.glow) {
          CubicKeyframe(1, duration: 0.5)
          CubicKeyframe(0.2, duration: 0.4)
          CubicKeyframe(1, duration: 0.5)
          CubicKeyframe(0, duration: 0.6)
        }
      }
      .onAppear(perform: showOff)
  }

  private func showOff() {
    guard store.justUnlocked == feature else { return }
    store.shownUnlock(feature)
    if !reduceMotion { glow += 1 }
  }
}

private struct Grow {
  var scale = 1.0
  var glow = 0.0
}
