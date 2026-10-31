#if DEBUG
  import ChessCore
  import Engine
  import Model
  import SwiftUI

  /// Debug builds open Survival on a run without taps, for screenshots:
  /// `SURVIVAL_SCREEN=run` (or `end`, ending it, or `blunder`, its last move
  /// the worst), playing your prep and then `SURVIVAL_PAST=n` engine moves
  /// past it, or `SURVIVAL_MOVES=n` of yours in all; `SURVIVAL_CLOCK=move10` and `SURVIVAL_FLASH=1` set the setup.
  /// `OPEN_MODE=survival` opens Survival itself: `RootView.debugMode`.
  @MainActor
  enum SurvivalDebug {
    struct Plan {
      var screen: String
      var past: Int
      /// At most this many of your moves, then the run is left as it stands.
      var cap: Int?
      var env: [String: String]

      func prefs(_ prefs: inout SurvivalPrefs) {
        if let clock = env["SURVIVAL_CLOCK"].flatMap(ClockMode.init(rawValue:)) { prefs.clock = clock }
        if env["SURVIVAL_FLASH"] == "1" { prefs.undefendedFlash = true }
      }
    }

    static var plan: Plan? {
      let env = ProcessInfo.processInfo.environment
      guard let screen = env["SURVIVAL_SCREEN"], screen != "setup" else { return nil }
      return Plan(screen: screen, past: Int(env["SURVIVAL_PAST"] ?? "") ?? 0, cap: Int(env["SURVIVAL_MOVES"] ?? ""), env: env)
    }

    static func drive(_ model: RunModel, _ plan: Plan) {
      guard plan.screen != "intro" else { return }
      Task {
        var past = 0, mine = 0
        while model.finish == nil {
          try? await Task.sleep(for: .milliseconds(250))
          if model.intro == .announce { model.toBoard() }
          if model.intro == .replay { model.skipIntro() }
          guard model.live, model.myTurn, !model.thinking, model.pending == nil, model.flash == nil, model.miss == nil else { continue }
          let fen = model.run.fen
          if let cap = plan.cap, mine >= cap { return }
          mine += 1
          if let san = model.prepNow.first, let move = applySan(fen, san) {
            model.play(move)
            continue
          }
          if past >= plan.past {
            if plan.screen == "end" { model.endRound() }
            return
          }
          past += 1
          let worst = plan.screen.hasPrefix("blunder") && past == plan.past
          let snap = await HintEngine.shared.analyse(fen, EngineLimits(depth: 4, multiPv: worst ? 30 : 1))
          guard model.run.fen == fen, let line = worst ? snap.lines.last : snap.lines.first,
            let uci = line.pv.first, let move = applyUci(fen, uci)
          else {
            mine -= 1
            continue
          }
          model.play(move)
        }
        if plan.screen == "blunder" { model.continueToEnd() }
      }
    }
  }
#endif

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
  /// Debug builds open a mode over the tabs with `OPEN_MODE=survival` (or `autopilot`, `growth`, `drill`, `play`), for screenshots.
  static var debugMode: Mode? {
    #if DEBUG
      switch ProcessInfo.processInfo.environment["OPEN_MODE"] {
      case "survival": .survival
      case "autopilot": .autopilot
      case "growth": .growth
      case "drill": .drill
      case "play": .play
      default: nil
      }
    #else
      nil
    #endif
  }
}
