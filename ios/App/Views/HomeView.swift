import ChessCore
import Game
import Model
import SwiftUI

/// Home: Play's next run on its button with the selection under it, Middlegame and
/// Endgames, Recommendations and Milestones. A mode tile starts the mode on
/// your saved settings; press and hold Middlegame for Start or Settings (its
/// setup screen first). A Pawn Shop feature shows only once it is yours. A
/// feature just bought gets a tip at its control, and enough pawns for
/// something in the Pawn Shop a tip on its tab.
struct HomeView: View {
  let tree: OpeningTree
  let onOpen: (Mode) -> Void
  /// Open a mode on its setup screen.
  let onSetup: (Mode) -> Void
  /// Fill a recommendation in Growth.
  let onGap: (Gap) -> Void
  /// Go to the Playbook tab, when there is nothing to play yet.
  let onPlaybook: () -> Void
  @Environment(AppStore.self) private var store
  @State private var settings = false

  var body: some View {
    ScrollView {
      VStack(spacing: 0) {
        HStack {
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
                .tip(text: tip == .middlegame ? tip?.text : nil, arrowAt: 0.3, minWidth: 260) { nextHomeTip(store) }
              tile("Endgames", "flag", .endgame).unlockedBy(.endgames, hidden: true)
                .tip(text: tip == .endgames ? tip?.text : nil, arrowAt: 0.7) { nextHomeTip(store) }
            }
            // Over the cards below while a tile's tip hangs past it.
            .zIndex(tip == .middlegame || tip == .endgames ? 1 : 0)
            .padding(.bottom, 10)
          }
          VStack(spacing: 10) {
            RecommendationsCard(tree: tree, onPick: onGap).unlockedBy(.recommendations, hidden: true)
              .tip(text: tip == .recommendations ? tip?.text : nil) { nextHomeTip(store) }
            MilestonesCard()
          }
        }
      }
      .padding(.horizontal, 16).padding(.bottom, 24)
    }
    // While a tip shows, a tap anywhere goes to the next one.
    .overlay {
      if tip != nil {
        SwiftUI.Color.black.opacity(0.001).contentShape(Rectangle())
          .onTapGesture { nextHomeTip(store) }
          .accessibilityHidden(true)
      }
    }
    // The Pawn Shop is the system tab bar's last of five, just under Home.
    .overlay(alignment: .bottom) {
      if tip == .shop {
        TipBubble(text: GameTip.shop.text, arrow: .down, arrowAt: 0.9) { nextHomeTip(store) }
          .padding(.horizontal, 16).padding(.bottom, 12)
      }
    }
    // Leaving Home puts its tip away, so a later one never waits behind it.
    .onDisappear { nextHomeTip(store) }
    .sheet(isPresented: $settings) { SettingsSheet().presentationBackground(Theme.background) }
    .onAppear {
      guard store.takeSettingsHeld() else { return }
      var still = Transaction()
      still.disablesAnimations = true
      withTransaction(still) { settings = true }
    }
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
  @ViewBuilder private func tile(_ name: String, _ icon: String, _ mode: Mode, held: Bool = false) -> some View {
    let button = Button { onOpen(mode) } label: {
      HStack(spacing: 10) {
        Icon(name: icon, size: 20).foregroundStyle(Theme.accent)
        Text(name).font(.system(size: 16, weight: .bold)).foregroundStyle(Theme.text)
        Spacer(minLength: 0)
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

/// Home's tip put away, for the next one.
@MainActor private func nextHomeTip(_ store: AppStore) {
  dismissTip(store, store.state.homeTip)
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
          .tip(text: tip == .sidePicker ? tip?.text : nil, arrowAt: 0.13, minWidth: 240) { nextHomeTip(store) }
          SegmentedControl(
            value: Binding(get: { settings.start }, set: { start in store.update { $0.settings.start = start } }),
            options: [(RunStart.freeform, "Freeform"), (RunStart.drill, "Drill")], track: Theme.background)
            .unlockedBy(.freeform, hidden: true)
            .tip(text: tip == .freeform ? tip?.text : nil) { nextHomeTip(store) }
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
      .tip(text: tip == .openingPicker ? tip?.text : nil) { nextHomeTip(store) }
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
    }
    .buttonStyle(.plain)
    .accessibilityLabel("\(store.shownPawns) pawns, Pawn Shop")
  }
}
