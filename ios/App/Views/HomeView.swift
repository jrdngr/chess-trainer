import ChessCore
import Game
import Model
import SwiftUI

/// Home: Play's next run on its button with the selection under it, Middlegame and
/// Endgames, the line on what the Playbook grows next, and Milestones. A mode tile starts the mode on
/// your saved settings; press and hold Middlegame for Start or Settings (its
/// setup screen first). A Pawn Shop feature shows only once it is yours. A
/// side picker or opening picker just bought gets a tip at its control.
struct HomeView: View {
  let tree: OpeningTree
  let onOpen: (Mode) -> Void
  /// Open a mode on its setup screen.
  let onSetup: (Mode) -> Void
  /// Open the Playbook tree at the opening that grows next.
  let onNext: (MapNode) -> Void
  /// Go to the Playbook tab, when there is nothing to play yet.
  let onPlaybook: () -> Void
  @Environment(AppStore.self) private var store
  @State private var settings = false

  var body: some View {
    ScrollView {
      VStack(spacing: 0) {
        HStack {
          if store.dev.daysAhead > 0 {
            // The developer tools' clock, so it isn't left ahead by mistake.
            Text("+\(store.dev.daysAhead) days").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.warn)
          }
          Spacer()
          HomePawns()
          Button { settings = true } label: {
            Icon(name: "gear", size: 20).foregroundStyle(Theme.text2).padding(.horizontal, 11).frame(minWidth: 44, minHeight: 44)
              .background(RoundedRectangle(cornerRadius: 14).fill(Theme.surface))
              .contentShape(RoundedRectangle(cornerRadius: 14))
          }
          .buttonStyle(.plain)
          .accessibilityLabel("Settings")
        }
        .padding(.top, 2).padding(.bottom, 12)
        VStack(spacing: 0) {
          play
            .padding([.top, .horizontal], 8)
          if [ShopFeature.sidePicker, .freeform, .openingPicker].contains(where: { store.state.owns($0) }) {
            PlayFooter(tip: tip)
          } else {
            SwiftUI.Color.clear.frame(height: 8)
          }
        }
        .background(RoundedRectangle(cornerRadius: 20).fill(Theme.surface))
        // Over the tiles below, so a tip hanging past the card stays on top.
        .zIndex(1)
        .padding(.bottom, 10)
        Group {
          if store.state.owns(.middlegame) || store.state.owns(.endgames) {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible())], spacing: 10) {
              tile("Middlegame", "middlegame", .middlegame, held: true).unlockedBy(.middlegame, hidden: true)
              tile("Endgames", "flag", .endgame, dot: !store.state.endgames.tuneUpsDue(now: Env.now()).isEmpty)
                .unlockedBy(.endgames, hidden: true)
            }
            .padding(.bottom, 10)
          }
          VStack(spacing: 10) {
            NextLine(tree: tree, onOpen: onNext)
            MilestonesCard()
          }
        }
      }
      .padding(.horizontal, 16).padding(.bottom, 24)
    }
    // The day's streak pawns pop out of the streak ring, once Home has laid out.
    .pawnFlights()
    .task {
      try? await Task.sleep(for: .milliseconds(400))
      store.showStreakPawns()
    }
    .sheet(isPresented: $settings) { SettingsSheet().presentationBackground(Theme.background) }
    .task {
      if Self.debugDeveloper { settings = true }
      guard store.takeSettingsHeld() else { return }
      // The old screens' Settings and Developer sheets are still going away: presented
      // now, Settings wouldn't show, yet would stay marked open and never open again.
      try? await Task.sleep(for: .milliseconds(600))
      var still = Transaction()
      still.disablesAnimations = true
      withTransaction(still) { settings = true }
    }
  }

  /// Debug builds open Settings and its Developer screen with `OPEN_DEV=1`, for screenshots.
  static var debugDeveloper: Bool {
    #if DEBUG
      ProcessInfo.processInfo.environment["OPEN_DEV"] != nil
    #else
      false
    #endif
  }

  private var tip: GameTip? { store.state.homeTip }

  /// Play's button, or that there is nothing to play yet.
  @ViewBuilder private var play: some View {
    let selection = store.peekRoundSelection()
    if nextRound(store.state, tree, selection, store.autoHistory) != nil {
      Button { onOpen(.play) } label: { PlayLabel() }
        .buttonStyle(PlayStackStyle())
    } else {
      Button { onPlaybook() } label: {
        HStack(spacing: 13) {
          Icon(name: "bolt", size: 22).foregroundStyle(Theme.accentInk).frame(width: 42, height: 42)
            .background(RoundedRectangle(cornerRadius: 14).fill(Theme.accent))
          VStack(alignment: .leading, spacing: 1) {
            Text("PLAY").font(.system(size: 10.5, weight: .heavy)).tracking(0.9).foregroundStyle(Theme.accent)
            Text("Build").font(.system(size: 18, weight: .heavy)).foregroundStyle(Theme.text)
            Text("Nothing to play yet \u{00b7} add an opening").font(.system(size: 12.5)).foregroundStyle(Theme.text2).lineLimit(1)
          }
          Spacer()
          Icon(name: "chevron", size: 20).foregroundStyle(Theme.text3)
        }
        .padding(.horizontal, 15).padding(.vertical, 14)
        .background(LinearGradient(
          colors: [Theme.accent.opacity(0.22), Theme.accent.opacity(0.1)], startPoint: .topLeading, endPoint: .bottomTrailing))
        .clipShape(RoundedRectangle(cornerRadius: 12))
      }
      .buttonStyle(.plain)
    }
  }

  /// A mode's tile. `held`: press and hold offers Start and Settings.
  /// `dot`: a plain dot, no count, while something waits there (an Endgames tune-up).
  @ViewBuilder private func tile(_ name: String, _ icon: String, _ mode: Mode, held: Bool = false, dot: Bool = false) -> some View {
    let button = Button { onOpen(mode) } label: {
      HStack(spacing: 10) {
        Icon(name: icon, size: 20).foregroundStyle(Theme.accent)
        Text(name).font(.system(size: 16, weight: .bold)).foregroundStyle(Theme.text)
        Spacer(minLength: 0)
        if dot { Circle().fill(Theme.accent).frame(width: 8, height: 8).accessibilityLabel("Tune-up due") }
      }
      .padding(.horizontal, 12).frame(minHeight: 56)
      .background(RoundedRectangle(cornerRadius: 20).fill(Theme.surface))
      .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: 20))
    }
    .buttonStyle(.plain)
    if held {
      button.contextMenu {
        Button { onOpen(mode) } label: { Label("Start", systemImage: "play.fill") }
        Button { onSetup(mode) } label: { Label("Settings", systemImage: "slider.horizontal.3") }
      }
    } else {
      button
    }
  }
}

/// The word on Home's Play button.
struct PlayLabel: View {
  var body: some View {
    let label = HStack(spacing: 10) {
      Image(systemName: "play.fill").font(.system(size: 18, weight: .bold))
      Text("Play").font(.system(size: 21, weight: .heavy))
    }
    ZStack {
      // The outline: sixteen copies in the outline color, pushed out in a ring.
      ForEach(0..<16, id: \.self) { i in
        let angle = Double(i) / 16 * 2 * .pi
        label.foregroundStyle(Theme.playOutline)
          .offset(x: cos(angle) * 1.75, y: sin(angle) * 1.75)
          .accessibilityHidden(true)
      }
      label.foregroundStyle(.white)
    }
  }
}

/// Home's Play button: the top card of a stack of three, each lower card narrower.
/// Pressed, the top card goes down into the stack and the stack closes under it.
struct PlayStackStyle: ButtonStyle {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  func makeBody(configuration: Configuration) -> some View {
    let down = configuration.isPressed
    let shape = RoundedRectangle(cornerRadius: 12)
    ZStack(alignment: .top) {
      shape.fill(Theme.deck3).frame(height: 54).padding(.horizontal, 14).offset(y: 8)
      shape.fill(Theme.deck2).frame(height: 54).padding(.horizontal, 7).offset(y: down && !reduceMotion ? 8 : 4)
      configuration.label
        .frame(maxWidth: .infinity, minHeight: 54)
        .background(shape.fill(down ? Theme.accentPressed : Theme.accent))
        .offset(y: down && !reduceMotion ? 8 : 0)
    }
    .frame(height: 62, alignment: .top)
    .contentShape(Rectangle())
    .animation(down ? .easeOut(duration: 0.07) : .timingCurve(0.2, 0.8, 0.3, 1, duration: 0.24), value: down)
    .sensoryFeedback(.impact(weight: .light), trigger: down) { _, pressed in pressed }
  }
}

/// Under Play's button on Home: the side, how runs start, and the opening, each with its tip once bought.
private struct PlayFooter: View {
  let tip: GameTip?
  @Environment(AppStore.self) private var store
  @State private var picking: SelectionPicking?

  var body: some View {
    let settings = store.state.settings
    VStack(spacing: 8) {
      if store.state.owns(.sidePicker) || store.state.owns(.freeform) {
        HStack(spacing: 8) {
          Button { picking = .color } label: {
            HStack(spacing: 6) {
              ColorSquare(choice: settings.selection.color, size: 20)
              Icon(name: "down", size: 14).foregroundStyle(Theme.text3)
            }
            .padding(.leading, 12).padding(.trailing, 10).frame(minHeight: 44)
            .background(RoundedRectangle(cornerRadius: 12).fill(Theme.surface2))
            .contentShape(RoundedRectangle(cornerRadius: 12))
          }
          .accessibilityLabel("Side")
          .unlockedBy(.sidePicker, hidden: true)
          // The side button is narrow: the tip keeps a readable width, its arrow at the button.
          .tip(text: tip == .sidePicker ? tip?.text : nil, arrowAt: 0.13, minWidth: 240) { dismissTip(store, .sidePicker) }
          SegmentedControl(
            value: Binding(get: { settings.start }, set: { start in store.update { $0.settings.start = start } }),
            options: [(RunStart.freeform, "Freeform"), (RunStart.drill, "Drill")], track: Theme.background)
            .unlockedBy(.freeform, hidden: true)
        }
        // Without the Freeform switch, the side button keeps to the left rather than the middle.
        .frame(maxWidth: .infinity, alignment: .leading)
        .zIndex(1)
      }
      Button { picking = .quick } label: {
        HStack(spacing: 8) {
          SelectionTrail(opening: settings.selection.opening).frame(maxWidth: .infinity, alignment: .leading)
          Icon(name: "down", size: 16).foregroundStyle(Theme.text3)
        }
        .padding(.horizontal, 14).frame(minHeight: 44)
        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.surface2))
        .contentShape(RoundedRectangle(cornerRadius: 12))
      }
      .unlockedBy(.openingPicker, hidden: true)
      .tip(text: tip == .openingPicker ? tip?.text : nil) { dismissTip(store, .openingPicker) }
    }
    .padding(8)
    .buttonStyle(.plain)
    .selectionSheets($picking)
  }
}

/// Your pawns beside the gear: a tap opens the Pawn Shop.
private struct HomePawns: View {
  @Environment(AppStore.self) private var store
  @Environment(\.openShop) private var openShop

  var body: some View {
    Button { openShop?("") } label: {
      PawnAmount(count: store.shownPawns)
        .padding(.horizontal, 12).frame(minHeight: 44)
        .background(RoundedRectangle(cornerRadius: 14).fill(Theme.surface))
        .contentShape(RoundedRectangle(cornerRadius: 14))
        .pawnSpot("counter")
    }
    .buttonStyle(.plain)
    .accessibilityLabel("\(store.shownPawns) pawns, Pawn Shop")
  }
}
