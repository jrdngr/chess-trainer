import ChessCore
import Game
import Model
import SwiftUI

/// Home: Play's next run on its button with the selection under it, Middlegame and
/// Endgames, Recommendations and Milestones. A mode tile starts the mode on
/// your saved settings; press and hold Middlegame for Start or Settings (its
/// setup screen first). During the tutorial, Home asks for one step between
/// games and the rest is locked; after its last game, a tip on the Playbook tab.
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
  @State private var confirmSkip = false

  /// The tutorial's step on Home, while it runs.
  private var tutorialHome: (step: TutorialStep, tip: String?)? {
    guard let tutorial = store.state.settings.tutorial else { return nil }
    let selection = store.state.settings.selection
    return tutorialStep(tutorial, color: selection.color, selected: nodeById(tree, selection.opening).sans)
  }
  private var locked: Bool { store.state.settings.tutorial != nil }

  var body: some View {
    let step = tutorialHome
    ScrollView {
      VStack(spacing: 0) {
        HStack {
          // Gone once the games are played: only the Playbook tab's tips are left then.
          if let tutorial = store.state.settings.tutorial, tutorial.played < TUTORIAL_GAMES {
            TutorialStrip(played: tutorial.played) { confirmSkip = true }
          }
          Spacer()
          Button { settings = true } label: {
            Icon(name: "gear", size: 20).foregroundStyle(Theme.text2).padding(.horizontal, 11).frame(minWidth: 44, minHeight: 44)
              .background(RoundedRectangle(cornerRadius: 14).fill(Theme.surface))
              .contentShape(RoundedRectangle(cornerRadius: 14))
          }
          .buttonStyle(.plain)
          .accessibilityLabel("Settings")
          .disabled(locked).opacity(locked ? 0.35 : 1)
        }
        .padding(.top, 2).padding(.bottom, 12)
        VStack(spacing: 0) {
          play
            .padding([.top, .horizontal], 8)
            .disabled(locked && step?.step != .play).opacity(locked && step?.step != .play ? 0.35 : 1)
            .tip(text: step?.step == .play ? step?.tip : nil, inset: 8)
          PlayFooter(step: step)
        }
        .background(RoundedRectangle(cornerRadius: 20).fill(Theme.surface))
        // Over the tiles below, so a tip hanging past the card stays on top.
        .zIndex(1)
        .padding(.bottom, 10)
        Group {
          LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible())], spacing: 10) {
            tile("Middlegame", "middlegame", .middlegame, held: true)
            tile("Endgames", "flag", .endgame)
          }
          VStack(spacing: 10) {
            RecommendationsCard(tree: tree, onPick: onGap)
            MilestonesCard()
          }
          .padding(.top, 10)
        }
        .disabled(locked).opacity(locked ? 0.35 : 1)
      }
      .padding(.horizontal, 16).padding(.bottom, 24)
    }
    // While a tip shows, a tap anywhere goes to the next one.
    .overlay {
      if tip != nil {
        SwiftUI.Color.black.opacity(0.001).contentShape(Rectangle())
          .onTapGesture { if !locked { nextHomeTip(store) } }
          .accessibilityHidden(true)
      }
    }
    // The Playbook tab is the system tab bar's second of four, just under Home.
    .overlay(alignment: .bottom) {
      if tip == .playbookTab {
        TipBubble(text: TutorialTip.playbookTab.text, arrow: .down, arrowAt: 0.38) { if !locked { nextHomeTip(store) } }
          .padding(.horizontal, 16).padding(.bottom, 12)
      }
    }
    // Leaving Home by the tab its last tip points at puts that tip away; in the tutorial, only that does.
    .onDisappear { if tip == .playbookTab { nextHomeTip(store) } }
    .sheet(isPresented: $settings) { SettingsSheet().presentationBackground(Theme.background) }
    // The tab bar waits for the tutorial's last game.
    .toolbar((store.state.settings.tutorial?.played ?? TUTORIAL_GAMES) < TUTORIAL_GAMES ? .hidden : .visible, for: .tabBar)
    .confirmationDialog("Skip the tutorial?", isPresented: $confirmSkip, titleVisibility: .visible) {
      Button("Skip tutorial", role: .destructive) { store.update { $0.settings.skipTutorial() } }
    } message: {
      Text("Your openings stay in your Playbook.")
    }
    .onAppear {
      guard store.takeSettingsHeld() else { return }
      var still = Transaction()
      still.disablesAnimations = true
      withTransaction(still) { settings = true }
    }
  }

  private var tip: TutorialTip? { homeTip(store.state.settings.tips) }

  /// Play's button, or that there is nothing to play yet.
  @ViewBuilder private var play: some View {
    let selection = store.peekRoundSelection()
    if store.state.settings.tutorial?.next != nil || nextRound(store.state, tree, selection, store.autoHistory) != nil {
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
    HStack(spacing: 10) {
      Image(systemName: "play.fill").font(.system(size: 18, weight: .bold))
      Text("Play").font(.system(size: 21, weight: .heavy))
    }
    .foregroundStyle(Theme.accentInk)
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
  dismissTip(store, homeTip(store.state.settings.tips))
}

/// Under Play's button on Home: the side, how runs start, and the opening.
/// During the tutorial only its step's control takes a tap.
private struct PlayFooter: View {
  let step: (step: TutorialStep, tip: String?)?
  @Environment(AppStore.self) private var store
  @State private var picking: SelectionPicking?

  var body: some View {
    let settings = store.state.settings
    let locked = step != nil
    VStack(spacing: 8) {
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
        .disabled(locked && step?.step != .side).opacity(locked && step?.step != .side ? 0.35 : 1)
        // The side button is narrow: the tip keeps a readable width, its arrow at the button.
        .tip(text: step?.step == .side ? step?.tip : nil, arrowAt: 0.13, minWidth: 240)
        SegmentedControl(
          value: Binding(get: { settings.start }, set: { start in store.update { $0.settings.start = start } }),
          options: [(RunStart.freeform, "Freeform"), (RunStart.drill, "Drill")], track: Theme.background)
          .disabled(locked).opacity(locked ? 0.35 : 1)
      }
      .zIndex(1)
      Button { picking = .quick } label: {
        HStack(spacing: 8) {
          SelectionTrail(opening: settings.selection.opening).frame(maxWidth: .infinity, alignment: .leading)
          Icon(name: "down", size: 16).foregroundStyle(Theme.text3)
        }
        .padding(.horizontal, 14).frame(minHeight: 44)
        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.surface2))
        .contentShape(RoundedRectangle(cornerRadius: 12))
      }
      .disabled(locked && step?.step != .opening).opacity(locked && step?.step != .opening ? 0.35 : 1)
      .tip(text: step?.step == .opening ? step?.tip : nil)
    }
    .padding(8)
    .buttonStyle(.plain)
    .selectionSheets($picking)
  }
}

/// The tutorial's progress on Home: a mark per game, and Skip.
private struct TutorialStrip: View {
  let played: Int
  let onSkip: () -> Void

  var body: some View {
    HStack(spacing: 10) {
      Text("Tutorial").font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.text2)
      HStack(spacing: 4) {
        ForEach(0..<TUTORIAL_GAMES, id: \.self) { game in
          RoundedRectangle(cornerRadius: 2).fill(game < played ? Theme.accent : Theme.surface3).frame(width: 18, height: 5)
        }
      }
      .accessibilityElement().accessibilityLabel("\(min(played, TUTORIAL_GAMES)) of \(TUTORIAL_GAMES) games played")
      Button("Skip", action: onSkip).font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.text2)
        .buttonStyle(.plain).frame(minHeight: 44)
    }
  }
}
