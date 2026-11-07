import SwiftUI

/// Debug builds open the end screen scrolled with `END_SCROLL=bottom` (or `middle`), for screenshots.
struct SurvivalDebugScroll: ViewModifier {
  func body(content: Content) -> some View {
    #if DEBUG
      switch ProcessInfo.processInfo.environment["END_SCROLL"] {
      case "bottom": content.defaultScrollAnchor(.bottom)
      case "middle": content.defaultScrollAnchor(UnitPoint(x: 0.5, y: 0.55))
      default: content
      }
    #else
      content
    #endif
  }
}

extension RootView {
  /// Debug builds open a mode over the tabs with `OPEN_MODE=autopilot` (or `endgame`, `middlegame`), for screenshots.
  static var debugMode: Mode? {
    #if DEBUG
      switch ProcessInfo.processInfo.environment["OPEN_MODE"] {
      case "autopilot": .autopilot
      case "endgame": .endgame
      case "middlegame": .middlegame
      default: nil
      }
    #else
      nil
    #endif
  }
}
